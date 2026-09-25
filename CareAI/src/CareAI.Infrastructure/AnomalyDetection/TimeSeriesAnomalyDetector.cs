using CareAI.Core.Entities;
using Microsoft.ML;
using Microsoft.ML.Transforms.TimeSeries;

namespace CareAI.Infrastructure.AnomalyDetection;

public sealed class TimeSeriesAnomalyDetector
{
    public HealthInsight? Detect(string elderId, string deviceId, string metric,
        IReadOnlyList<HealthMeasurement> measurements, DateTime windowEndLocal,
        TimeZoneInfo zone, AnomalyDetectionOptions options, CancellationToken ct)
    {
        var isHeart = metric == "HEART_RATE";
        var duration = isHeart ? 8 : 6; // 22:00–06:00 and 06:00–12:00.
        var daily = new List<(int Offset, float Value)>();
        for (var offset = -13; offset <= 0; offset++)
        {
            ct.ThrowIfCancellationRequested();
            var end = windowEndLocal.AddDays(offset);
            var start = end.AddHours(-duration);
            var startUtc = TimeZoneInfo.ConvertTimeToUtc(start, zone);
            var endUtc = TimeZoneInfo.ConvertTimeToUtc(end, zone);
            var samples = measurements.Where(m => m.Timestamp >= startUtc && m.Timestamp < endUtc
                && double.IsFinite(m.Value) && (isHeart ? m.Value > 0 : m.Value >= 0)).ToArray();
            var hours = samples.Select(m => TimeZoneInfo.ConvertTimeFromUtc(
                DateTime.SpecifyKind(m.Timestamp, DateTimeKind.Utc), zone))
                .GroupBy(t => (t.Date, t.Hour)).Count();
            if (hours < duration) continue; // Missing data must never become zero activity.
            var value = isHeart ? samples.Average(m => m.Value) : samples.Sum(m => m.Value);
            if (value <= float.MaxValue) daily.Add((offset, (float)value));
        }

        if (daily.Count < options.MinimumBaselineDays + 1 || daily[^1].Offset != 0) return null;
        var baseline = daily.Take(daily.Count - 1).Average(d => (double)d.Value);
        var observed = daily[^1].Value;
        var ml = new MLContext(seed: 42);
        var input = ml.Data.LoadFromEnumerable(daily.Select(d => new TimeSeriesInput { Value = d.Value }));
        var estimator = ml.Transforms.DetectIidSpike(nameof(SpikePrediction.Prediction),
            nameof(TimeSeriesInput.Value), options.Confidence, daily.Count - 1,
            isHeart ? AnomalySide.Positive : AnomalySide.Negative);
        // IID's Fit does not train a baseline; ordered Transform warms the detector
        // on prior days before scoring the final (held-out) day.
        var model = estimator.Fit(ml.Data.LoadFromEnumerable(Array.Empty<TimeSeriesInput>()));
        SpikePrediction? last = null;
        foreach (var prediction in ml.Data.CreateEnumerable<SpikePrediction>(model.Transform(input), false))
        {
            ct.ThrowIfCancellationRequested();
            last = prediction;
        }
        var score = last!.Prediction;
        var zeroSteps = !isHeart && observed == 0 && baseline >= options.MinimumUsualMorningSteps
            && daily.Take(daily.Count - 1).Count(d => d.Value > 0) >= options.MinimumBaselineDays;
        if (isHeart ? score[0] != 1 || observed <= baseline : !zeroSteps) return null;
        return new HealthInsight
        {
            ElderProfileId = elderId, DeviceId = deviceId,
            InsightType = isHeart ? "NIGHT_HEART_RATE_SPIKE" : "MORNING_ZERO_STEPS",
            WindowEndUtc = TimeZoneInfo.ConvertTimeToUtc(windowEndLocal, zone),
            ObservedValue = observed, BaselineValue = baseline, PValue = score[2],
            Description = isHeart
                ? "Elevated nighttime mean heart rate relative to personal history (IID spike). Nighttime is a proxy for sleep."
                : "Explicit zero morning steps despite usual activity (zero-step rule, with IID p-value)."
        };
    }
}
