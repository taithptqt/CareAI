using CareAI.Core.Entities;
using CareAI.Infrastructure.AnomalyDetection;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace CareAI.UnitTests;

public class AnomalyDetectionTests
{
    private static readonly DateTime End = new(2026, 9, 24, 12, 0, 0);

    private static List<HealthMeasurement> Samples(bool heart, double target)
    {
        var end = heart ? End.AddHours(-6) : End;
        var hours = heart ? 8 : 6;
        return Enumerable.Range(-13, 14).SelectMany(day => Enumerable.Range(0, hours)
            .Select(hour => new HealthMeasurement
            {
                ElderProfileId = "elder", DeviceId = "watch",
                MetricType = heart ? "HEART_RATE" : "STEPS",
                Timestamp = end.AddDays(day).AddHours(-hours + hour),
                Value = day == 0 ? target : heart ? 60 + (day % 3) : 100
            })).ToList();
    }

    private static HealthInsight? Detect(List<HealthMeasurement> samples, bool heart = false,
        CancellationToken ct = default) => new TimeSeriesAnomalyDetector().Detect(
            "elder", "watch", heart ? "HEART_RATE" : "STEPS", samples,
            heart ? End.AddHours(-6) : End, TimeZoneInfo.Utc, new AnomalyDetectionOptions(), ct);

    [Fact]
    public void ExplicitZeroMorningAfterActiveHistoryCreatesInsight()
    {
        var insight = Detect(Samples(false, 0));
        Assert.NotNull(insight);
        Assert.Equal("MORNING_ZERO_STEPS", insight.InsightType);
        Assert.Equal(600, insight.BaselineValue);
        Assert.Equal(0, insight.ObservedValue);
    }

    [Fact]
    public void MissingMorningDoesNotBecomeZero()
    {
        var samples = Samples(false, 0);
        samples.RemoveAll(m => m.Timestamp >= End.AddHours(-6));
        Assert.Null(Detect(samples));
    }

    [Fact]
    public void IncompleteCoverageDoesNotCreateInsight()
    {
        var samples = Samples(false, 0);
        samples.RemoveAll(m => m.Timestamp == End.AddHours(-1));
        Assert.Null(Detect(samples));
    }

    [Fact]
    public void InsufficientHistoryIsSkipped() => Assert.Null(Detect(
        Samples(false, 0).Where(m => m.Timestamp >= End.AddDays(-3)).ToList()));

    [Fact]
    public void NormalActivityDoesNotCreateInsight() => Assert.Null(Detect(Samples(false, 100)));

    [Fact]
    public void NighttimeIncreaseTriggersPositiveSpike() => Assert.NotNull(Detect(Samples(true, 150), true));

    [Fact]
    public void NighttimeDecreaseDoesNotTriggerPositiveSpike() => Assert.Null(Detect(Samples(true, 30), true));

    [Fact]
    public async Task WorkerPersistsAndDoesNotDuplicateOnRerun()
    {
        var services = new ServiceCollection();
        var database = Guid.NewGuid().ToString();
        services.AddDbContext<CareAiDbContext>(o => o.UseInMemoryDatabase(database));
        services.AddSingleton<TimeSeriesAnomalyDetector>();
        await using var provider = services.BuildServiceProvider();
        await using (var seed = provider.CreateAsyncScope())
        {
            var db = seed.ServiceProvider.GetRequiredService<CareAiDbContext>();
            db.ElderProfiles.Add(new ElderProfile { Id = "elder" });
            db.HealthMeasurements.AddRange(Samples(false, 0));
            await db.SaveChangesAsync();
        }
        var worker = new AnomalyDetectionWorker(provider.GetRequiredService<IServiceScopeFactory>(),
            Options.Create(new AnomalyDetectionOptions { TimeZoneId = "UTC" }),
            NullLogger<AnomalyDetectionWorker>.Instance);
        var runAt = End.Date.AddDays(1).AddHours(2);
        await worker.RunOnceAsync(runAt, CancellationToken.None);
        await worker.RunOnceAsync(runAt, CancellationToken.None);
        await using var check = provider.CreateAsyncScope();
        var insights = await check.ServiceProvider.GetRequiredService<CareAiDbContext>()
            .HealthInsights.ToListAsync();
        Assert.Single(insights);
        Assert.Equal(End, insights[0].WindowEndUtc);
    }

    [Fact]
    public void CancellationIsHonored()
    {
        using var source = new CancellationTokenSource();
        source.Cancel();
        Assert.Throws<OperationCanceledException>(() => Detect(Samples(false, 0), ct: source.Token));
    }
}
