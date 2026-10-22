using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;

namespace CareAI.UnitTests;

public class ElderOverviewTests
{
    private static CareAiDbContext CreateDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Overview_{Guid.NewGuid():N}").Options);

    private static HealthMeasurement Sample(string elder, string metric, double value, DateTime time) => new()
    {
        ElderProfileId = elder, MetricType = metric, Value = value,
        Unit = metric == "HEART_RATE" ? "bpm" : "%", Timestamp = time, RecordedAt = time
    };

    [Fact]
    public async Task GetMyElders_RejectsMissingIdentity()
    {
        await using var db = CreateDb();
        var controller = new CaregiversController(db, NullLogger<CaregiversController>.Instance)
        { ControllerContext = new() { HttpContext = new DefaultHttpContext() } };
        Assert.IsType<UnauthorizedObjectResult>(await controller.GetMyElders(default));
    }

    [Fact]
    public async Task GetMyElders_OnlyIncludesActiveAssignmentsAndTheirMeasurements()
    {
        await using var db = CreateDb();
        foreach (var id in new[] { "allowed", "revoked", "other" })
        {
            db.ElderProfiles.Add(new ElderProfile { Id = id, FullName = $"Fixture {id}" });
            db.ElderCaregivers.Add(new ElderCaregiver
            {
                ElderProfileId = id, CaregiverId = id == "other" ? "someone-else" : "caregiver",
                IsActive = id != "revoked"
            });
            db.HealthMeasurements.Add(Sample(id, "HEART_RATE", 72, DateTime.UtcNow.AddMinutes(-3)));
        }
        await db.SaveChangesAsync();
        var controller = new CaregiversController(db, NullLogger<CaregiversController>.Instance)
        {
            ControllerContext = new() { HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                    [new Claim(ClaimTypes.NameIdentifier, "caregiver")], "test"))
            } }
        };
        var response = Assert.IsType<OkObjectResult>(await controller.GetMyElders(default));
        var item = Assert.Single(Assert.IsType<List<ElderItemDto>>(response.Value));
        Assert.Equal("allowed", item.Id);
        Assert.Equal(72, item.HealthOverview!.LatestHeartRate!.Value);
        Assert.Null(item.HealthOverview.LatestSpO2);
        Assert.Null(item.HealthOverview.TodaySteps);
        Assert.Null(item.HealthOverview.LastSyncedAt);
    }

    [Fact]
    public async Task Overview_ExcludesDemoAndFutureSamplesAndPreservesActualMeasurementTime()
    {
        await using var db = CreateDb();
        var now = new DateTime(2026, 10, 23, 10, 0, 0, DateTimeKind.Utc);
        var oldTime = now.AddDays(-2);
        db.HealthMeasurements.AddRange(
            Sample("elder", "HEART_RATE", 65, oldTime.AddMinutes(-1)),
            Sample("elder", "HEART_RATE", 72, oldTime),
            Sample("elder", "DEMO_HEART_RATE", 150, now.AddMinutes(-1)),
            Sample("elder", "SPO2", 98, now.AddMinutes(1)),
            Sample("someone-else", "SPO2", 97, now.AddMinutes(-1)));
        await db.SaveChangesAsync();
        var results = await new ElderOverviewReader(db).LoadAsync(["elder", "empty"], now);
        Assert.Equal(72, results["elder"].LatestHeartRate!.Value);
        Assert.Equal(oldTime, results["elder"].LatestHeartRate!.Timestamp);
        Assert.Equal(DateTimeKind.Utc, results["elder"].LatestHeartRate!.Timestamp.Kind);
        Assert.Null(results["elder"].LatestSpO2);
        Assert.Null(results["empty"].LatestHeartRate);
        Assert.DoesNotContain("someone-else", results.Keys);
    }

    [Fact]
    public async Task Overview_StepsUseVietnamDayAndDistinguishMissingFromMeasuredZero()
    {
        await using var db = CreateDb();
        var now = new DateTime(2026, 10, 23, 18, 0, 0, DateTimeKind.Utc);
        db.HealthMeasurements.AddRange(
            Sample("elder", "STEPS", 900, now.Date.AddHours(16)),
            Sample("elder", "STEPS", 100, now.Date.AddHours(17)),
            Sample("elder", "STEPS", 25, now.AddMinutes(-1)),
            Sample("elder", "STEPS", 500, now.AddMinutes(1)),
            Sample("zero", "STEPS", 0, now.AddMinutes(-1)));
        await db.SaveChangesAsync();
        var result = await new ElderOverviewReader(db).LoadAsync(["elder", "zero", "missing"], now);
        Assert.Equal(125, result["elder"].TodaySteps);
        Assert.Equal(now.AddMinutes(-1), result["elder"].StepsMeasuredAt);
        Assert.Equal(0, result["zero"].TodaySteps);
        Assert.Null(result["missing"].TodaySteps);
        Assert.Null(result["missing"].StepsMeasuredAt);
    }
}
