using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Services;

/// <summary>Read-only, batched overview for an already-authorized set of elders.</summary>
public sealed class ElderOverviewReader(CareAiDbContext db)
{
    public async Task<Dictionary<string, ElderHealthOverviewDto>> LoadAsync(
        string[] elderIds, DateTime nowUtc, CancellationToken ct = default)
    {
        if (elderIds.Length == 0) return [];

        // Exact metric names keep simulated measurements out of the real overview.
        var latest = await db.HealthMeasurements.AsNoTracking()
            .Where(m => elderIds.Contains(m.ElderProfileId) && m.Timestamp <= nowUtc &&
                (m.MetricType == "HEART_RATE" || m.MetricType == "SPO2"))
            .GroupBy(m => new { m.ElderProfileId, m.MetricType })
            .Select(g => g.OrderByDescending(m => m.Timestamp)
                .ThenByDescending(m => m.Id).First())
            .ToListAsync(ct);

        var dayStartUtc = nowUtc.AddHours(7).Date.AddHours(-7);
        var steps = await db.HealthMeasurements.AsNoTracking()
            .Where(m => elderIds.Contains(m.ElderProfileId) && m.MetricType == "STEPS" &&
                m.Timestamp >= dayStartUtc && m.Timestamp <= nowUtc)
            .GroupBy(m => m.ElderProfileId)
            .Select(g => new { ElderId = g.Key, Total = g.Sum(m => m.Value),
                MeasuredAt = g.Max(m => m.Timestamp) })
            .ToDictionaryAsync(s => s.ElderId, ct);

        var measurements = latest.ToLookup(m => m.ElderProfileId);
        return elderIds.Distinct().ToDictionary(id => id, id =>
        {
            var samples = measurements[id].ToList();
            steps.TryGetValue(id, out var dailySteps);
            return new ElderHealthOverviewDto(
                ToVital(samples.FirstOrDefault(m => m.MetricType == "HEART_RATE")),
                ToVital(samples.FirstOrDefault(m => m.MetricType == "SPO2")),
                dailySteps == null ? null : (int)dailySteps.Total,
                dailySteps == null ? null : DateTime.SpecifyKind(dailySteps.MeasuredAt, DateTimeKind.Utc));
        });
    }

    // Overview values are observations; clinical rules and alert generation stay elsewhere.
    private static VitalSignDto? ToVital(HealthMeasurement? sample) => sample == null
        ? null : new(sample.MetricType, sample.Value, sample.Unit,
            DateTime.SpecifyKind(sample.Timestamp, DateTimeKind.Utc), "GREY");
}
