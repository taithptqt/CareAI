using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.WeeklyReports;

public sealed class WeeklyReportService(CareAiDbContext db, PiiAnonymizerService anonymizer,
    GeminiWeeklyReportClient generator, IOptions<WeeklyReportOptions> options,
    ILogger<WeeklyReportService> logger)
{
    // Latest due Sunday. Report covers seven complete local days, ending Sunday 00:00.
    public static DateTime LatestDueSunday(DateTime utcNow, TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTimeFromUtc(DateTime.SpecifyKind(utcNow, DateTimeKind.Utc), zone);
        var sunday = local.Date.AddDays(-(int)local.DayOfWeek);
        if (local < sunday.AddHours(7)) sunday = sunday.AddDays(-7);
        return sunday;
    }

    public async Task GenerateForElderAsync(string elderId, DateTime utcNow, CancellationToken ct)
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById(options.Value.TimeZoneId);
        var endLocal = LatestDueSunday(utcNow, zone);
        var startUtc = TimeZoneInfo.ConvertTimeToUtc(endLocal.AddDays(-7), zone);
        var endUtc = TimeZoneInfo.ConvertTimeToUtc(endLocal, zone);
        if (await db.WeeklyHealthReports.AnyAsync(r => r.ElderProfileId == elderId && r.WeekEndUtc == endUtc, ct)) return;
        var rows = await db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == elderId && m.Timestamp >= startUtc && m.Timestamp < endUtc
                && (m.MetricType == "HEART_RATE" || m.MetricType == "STEPS" || m.MetricType == "SPO2"))
            .ToListAsync(ct);
        var alertCount = await db.HealthInsights.CountAsync(i => i.ElderProfileId == elderId
            && i.WindowEndUtc >= startUtc && i.WindowEndUtc < endUtc, ct);
        var data = anonymizer.Anonymize(rows, alertCount, startUtc, endUtc, zone);
        var generated = await generator.GenerateAsync(data, ct);
        var report = new WeeklyHealthReport
        {
            ElderProfileId = elderId, WeekStartUtc = startUtc, WeekEndUtc = endUtc,
            Content = generated.Content, Source = generated.Source
        };
        db.WeeklyHealthReports.Add(report);
        var recipients = await db.CaregiverPushTokens.Where(t => t.IsActive && db.ElderCaregivers
            .Any(ec => ec.IsActive && ec.ElderProfileId == elderId && ec.CaregiverId == t.CaregiverId))
            .Select(t => t.Id).ToListAsync(ct);
        foreach (var tokenId in recipients)
            db.WeeklyReportNotifications.Add(new WeeklyReportNotification
            { WeeklyHealthReport = report, CaregiverPushTokenId = tokenId });
        try
        {
            // SQL Server SaveChanges is transactional: report and outbox commit together.
            await db.SaveChangesAsync(ct);
            logger.LogInformation("Weekly report persisted ({Source}); queued {Count} notifications", generated.Source, recipients.Count);
        }
        catch (DbUpdateException ex) when (ex.InnerException is SqlException sql && sql.Number is 2601 or 2627)
        {
            logger.LogDebug("Weekly report was already persisted by another instance");
            db.ChangeTracker.Clear();
        }
    }
}
