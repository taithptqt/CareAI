using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.WeeklyReports;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.BackgroundWorkers;

public sealed class WeeklyReportNotificationWorker(IServiceScopeFactory scopes, IWeeklyReportPushSender sender,
    IOptions<ReportPushOptions> options, ILogger<WeeklyReportNotificationWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Value.Enabled)
        {
            logger.LogInformation("Report push disabled; notifications remain queued until configured");
            return;
        }
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try { await DispatchAsync(stoppingToken); }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { throw; }
                catch (Exception ex) { logger.LogError("Report notification dispatch failed ({Type})", ex.GetType().Name); }
                await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }

    public async Task DispatchAsync(CancellationToken ct)
    {
        if (!options.Value.Enabled) return;
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var now = DateTime.UtcNow;
        var items = await db.WeeklyReportNotifications.Include(n => n.WeeklyHealthReport)
            .Where(n => n.Status == "PENDING" && n.NextAttemptUtc <= now)
            .OrderBy(n => n.Id).Take(50).ToListAsync(ct);
        foreach (var item in items)
        {
            ct.ThrowIfCancellationRequested();
            // RowVersion makes lease acquisition atomic across instances; lease expires after crashes.
            item.NextAttemptUtc = DateTime.UtcNow.AddMinutes(2);
            try { await db.SaveChangesAsync(ct); }
            catch (DbUpdateConcurrencyException) { db.Entry(item).State = EntityState.Detached; continue; }
            var token = await db.CaregiverPushTokens.AsNoTracking().FirstOrDefaultAsync(t =>
                t.Id == item.CaregiverPushTokenId && t.IsActive, ct);
            var allowed = token is not null && await db.ElderCaregivers.AnyAsync(ec => ec.IsActive
                && ec.CaregiverId == token.CaregiverId && ec.ElderProfileId == item.WeeklyHealthReport.ElderProfileId, ct);
            if (!allowed) item.Status = "CANCELLED";
            else
            {
                try
                {
                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    timeout.CancelAfter(TimeSpan.FromSeconds(15));
                    await sender.SendAsync(token!.PushToken, item.WeeklyHealthReportId,
                        item.WeeklyHealthReport.ElderProfileId, timeout.Token);
                    item.Status = "SENT";
                    item.SentAt = DateTime.UtcNow;
                }
                catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
                catch (Exception ex)
                {
                    item.RetryCount++;
                    item.NextAttemptUtc = DateTime.UtcNow.AddMinutes(Math.Min(360, Math.Pow(2, Math.Min(9, item.RetryCount))));
                    logger.LogWarning("Report push deferred ({Type}), attempt {Attempt}", ex.GetType().Name, item.RetryCount);
                }
            }
            await db.SaveChangesAsync(ct);
            db.Entry(item).State = EntityState.Detached;
        }
    }
}
