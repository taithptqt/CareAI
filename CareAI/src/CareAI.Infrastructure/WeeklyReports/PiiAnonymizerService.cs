using CareAI.Core.Entities;

namespace CareAI.Infrastructure.WeeklyReports;

// Closed, numeric allowlist. No identities, free text, timestamps, or device IDs
// may cross the AI boundary. Aggregates remain sensitive health information.
public sealed record AnonymousWeeklyStatistics(
    double? AverageHeartRate, double? AverageDailySteps,
    int HeartRateDays, int StepDays, int AlertCount);

public sealed class PiiAnonymizerService
{
    public AnonymousWeeklyStatistics Anonymize(IEnumerable<HealthMeasurement> measurements,
        int alertCount, DateTime startUtc, DateTime endUtc, TimeZoneInfo zone)
    {
        var valid = measurements.Where(m => m.Timestamp >= startUtc && m.Timestamp < endUtc
            && double.IsFinite(m.Value)).ToArray();
        var heart = valid.Where(m => m.MetricType == "HEART_RATE" && m.Value > 0 && m.Value <= 300).ToArray();
        DateTime Day(HealthMeasurement m) => TimeZoneInfo.ConvertTimeFromUtc(
            DateTime.SpecifyKind(m.Timestamp, DateTimeKind.Utc), zone).Date;
        // Select a consistent source for the entire week; never sum across devices.
        var steps = valid.Where(m => m.MetricType == "STEPS" && m.Value >= 0 && m.Value <= 100000)
            .GroupBy(m => m.DeviceId).OrderByDescending(g => g.Select(Day).Distinct().Count())
            .ThenBy(g => g.Key, StringComparer.Ordinal).FirstOrDefault();
        var dailySteps = steps?.GroupBy(Day).Select(g => g.Sum(m => m.Value)).ToArray() ?? [];
        return new AnonymousWeeklyStatistics(
            heart.Length == 0 ? null : Math.Round(heart.Average(m => m.Value), 1),
            dailySteps.Length == 0 ? null : Math.Round(dailySteps.Average(), 0),
            heart.Select(Day).Distinct().Count(), dailySteps.Length, Math.Max(0, alertCount));
    }
}
