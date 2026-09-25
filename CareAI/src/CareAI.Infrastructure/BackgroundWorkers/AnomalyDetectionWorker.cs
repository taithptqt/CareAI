using CareAI.Core.Entities;
using CareAI.Infrastructure.AnomalyDetection;
using CareAI.Infrastructure.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.BackgroundWorkers;

public sealed class AnomalyDetectionWorker(
    IServiceScopeFactory scopeFactory, IOptions<AnomalyDetectionOptions> options,
    ILogger<AnomalyDetectionWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var settings = options.Value;
        var zone = TimeZoneInfo.FindSystemTimeZoneById(settings.TimeZoneId);
        logger.LogInformation("Anomaly worker started; daily 02:00 in {TimeZone}", zone.Id);
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                var now = DateTime.UtcNow;
                var localNow = TimeZoneInfo.ConvertTimeFromUtc(now, zone);
                var next = localNow.Date.AddHours(2);
                if (next <= localNow) next = next.AddDays(1);
                // Skip nonexistent local times and run only once on ambiguous days.
                while (zone.IsInvalidTime(next)) next = next.AddMinutes(1);
                var nextUtc = TimeZoneInfo.ConvertTimeToUtc(next, zone);
                logger.LogInformation("Next anomaly analysis at {NextUtc}", nextUtc);
                await Task.Delay(nextUtc - now, stoppingToken);
                try
                {
                    await RunOnceAsync(DateTime.UtcNow, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { throw; }
                catch (Exception ex) { logger.LogError(ex, "Anomaly analysis failed; retry at next scheduled run"); }
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            logger.LogInformation("Anomaly worker stopped");
        }
    }

    public async Task RunOnceAsync(DateTime utcNow, CancellationToken ct)
    {
        var settings = options.Value;
        var zone = TimeZoneInfo.FindSystemTimeZoneById(settings.TimeZoneId);
        var localNow = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc), zone);
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var detector = scope.ServiceProvider.GetRequiredService<TimeSeriesAnomalyDetector>();
        var elders = await db.ElderProfiles.AsNoTracking().Select(e => e.Id).ToListAsync(ct);
        logger.LogInformation("Starting 14-day anomaly analysis for {Count} elders", elders.Count);
        foreach (var elderId in elders)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                foreach (var metric in new[] { "HEART_RATE", "STEPS" })
                {
                    var endLocal = localNow.Date.AddHours(metric == "HEART_RATE" ? 6 : 12);
                    if (endLocal > localNow) endLocal = endLocal.AddDays(-1);
                    var endUtc = TimeZoneInfo.ConvertTimeToUtc(endLocal, zone);
                    var startUtc = TimeZoneInfo.ConvertTimeToUtc(endLocal.AddDays(-13)
                        .AddHours(metric == "HEART_RATE" ? -8 : -6), zone);
                    var rows = await db.HealthMeasurements.AsNoTracking()
                        .Where(m => m.ElderProfileId == elderId && m.MetricType == metric
                            && m.Timestamp >= startUtc && m.Timestamp < endUtc)
                        .OrderBy(m => m.Timestamp).ToListAsync(ct);
                    logger.LogDebug("Loaded {Count} {Metric} samples for {Elder}", rows.Count, metric, elderId);
                    foreach (var device in rows.GroupBy(m => m.DeviceId))
                    {
                        var insight = detector.Detect(elderId, device.Key, metric, device.ToArray(),
                            endLocal, zone, settings, ct);
                        if (insight is null) continue;
                        if (await db.HealthInsights.AnyAsync(i => i.ElderProfileId == elderId
                            && i.DeviceId == insight.DeviceId && i.InsightType == insight.InsightType
                            && i.WindowEndUtc == insight.WindowEndUtc, ct)) continue;
                        db.HealthInsights.Add(insight);
                        try
                        {
                            await db.SaveChangesAsync(ct);
                            logger.LogInformation("Saved {Type} insight for {Elder}, window {End}",
                                insight.InsightType, elderId, endUtc);
                        }
                        catch (DbUpdateException ex) when (ex.InnerException is SqlException sql
                            && sql.Number is 2601 or 2627)
                        {
                            logger.LogDebug("Insight already saved by another worker for {Elder}", elderId);
                        }
                        finally { db.Entry(insight).State = EntityState.Detached; }
                    }
                }
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
            catch (Exception ex)
            {
                logger.LogError(ex, "Anomaly analysis failed for {Elder}; continuing with next elder", elderId);
                db.ChangeTracker.Clear();
            }
        }
        logger.LogInformation("Anomaly analysis completed");
    }
}
