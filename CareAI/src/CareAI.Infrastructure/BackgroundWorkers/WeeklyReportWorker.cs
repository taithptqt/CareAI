using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.WeeklyReports;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.BackgroundWorkers;

public sealed class WeeklyReportWorker(IServiceScopeFactory scopes, IOptions<WeeklyReportOptions> options,
    ILogger<WeeklyReportWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById(options.Value.TimeZoneId);
        logger.LogInformation("Weekly reports scheduled Sunday 07:00 in {Zone}; latest missed week recovered on startup", zone.Id);
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                try { await RunOnceAsync(DateTime.UtcNow, stoppingToken); }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { throw; }
                catch (Exception ex) { logger.LogError(ex, "Weekly report cycle failed; will retry"); }
                var now = DateTime.UtcNow;
                var local = TimeZoneInfo.ConvertTimeFromUtc(now, zone);
                var next = local.Date.AddDays((7 - (int)local.DayOfWeek) % 7).AddHours(7);
                if (next <= local) next = next.AddDays(7);
                while (zone.IsInvalidTime(next)) next = next.AddMinutes(1);
                var delay = TimeZoneInfo.ConvertTimeToUtc(next, zone) - now;
                // Retry transient persistence failures without waiting another week.
                await Task.Delay(delay < TimeSpan.FromMinutes(15) ? delay : TimeSpan.FromMinutes(15), stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        { logger.LogInformation("Weekly report worker stopped"); }
    }

    public async Task RunOnceAsync(DateTime utcNow, CancellationToken ct)
    {
        await using var scope = scopes.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var ids = await db.ElderProfiles.AsNoTracking().Select(e => e.Id).ToListAsync(ct);
        foreach (var id in ids)
        {
            ct.ThrowIfCancellationRequested();
            await using var elderScope = scopes.CreateAsyncScope();
            try
            {
                await elderScope.ServiceProvider.GetRequiredService<WeeklyReportService>()
                    .GenerateForElderAsync(id, utcNow, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex) { logger.LogError(ex, "Could not persist weekly report for {Elder}; continuing", id); }
        }
    }
}
