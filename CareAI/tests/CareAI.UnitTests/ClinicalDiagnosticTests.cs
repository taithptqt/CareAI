using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Core.DTOs;
using CareAI.API.Controllers;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class ClinicalDiagnosticTests
{
    [Theory]
    [InlineData(179, false)]
    [InlineData(180, true)]
    [InlineData(35, true)]
    [InlineData(36, false)]
    public async Task CriticalBoundaries(double bpm, bool expected)
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var incident = await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", bpm);
        Assert.Equal(expected, incident?.Severity == IncidentSeverity.Critical);
        if (bpm == 36) Assert.Equal(IncidentSeverity.High, incident!.Severity);
    }

    [Fact]
    public async Task Surge_RequiresRestAndThreePriorSamples_AtMedianBoundary()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var at = DateTime.UtcNow;
        AddSample(db, "HEART_RATE", 80, at.AddMinutes(-4));
        AddSample(db, "HEART_RATE", 81, at.AddMinutes(-3));
        await db.SaveChangesAsync();
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 96, measuredAtUtc: at));

        AddSample(db, "HEART_RATE", 82, at.AddMinutes(-2));
        await db.SaveChangesAsync();
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 96, measuredAtUtc: at));

        AddSample(db, "STEPS", 1000, at.AddMinutes(-4));
        AddSample(db, "STEPS", 1007, at.AddMinutes(-1));
        await db.SaveChangesAsync();
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 95, measuredAtUtc: at));
        var incident = await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 96, measuredAtUtc: at);
        Assert.NotNull(incident);
        Assert.Equal(EmergencyType.Surge, incident.EmergencyType);
        Assert.Equal(IncidentSeverity.High, incident.Severity);
    }

    [Fact]
    public async Task ActivitySuppressesSurge_AndInvalidSamplesAreIgnored()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var at = DateTime.UtcNow;
        for (var n = 1; n <= 3; n++) AddSample(db, "HEART_RATE", 80, at.AddMinutes(-n));
        AddSample(db, "STEPS", 100, at.AddMinutes(-4));
        AddSample(db, "STEPS", 130, at.AddMinutes(-1));
        await db.SaveChangesAsync();
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 96, measuredAtUtc: at));
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 0));
        Assert.Null(await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", double.NaN));
    }

    [Fact]
    public async Task CooldownSuppressesRepeatedHighWarning_ButCriticalBypassesIt()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var engine = Engine(db);
        var first = await engine.EvaluateHeartRateSampleAsync("elder", "device", 38);
        Assert.NotNull(first);
        Assert.Equal(IncidentSeverity.High, first.Severity);
        first.Status = IncidentStatus.Resolved;
        await db.SaveChangesAsync();
        Assert.Null(await engine.EvaluateHeartRateSampleAsync("elder", "device", 38));
        var critical = await engine.EvaluateHeartRateSampleAsync("elder", "device", 35);
        Assert.NotNull(critical);
        Assert.NotEqual(first.Id, critical.Id);
        Assert.Single(db.ClinicalRuleCooldowns.Where(c => c.RuleCode == "HR_CRITICAL_LOW"));
        Assert.Equal(2, await db.Incidents.CountAsync());
    }

    [Fact]
    public async Task AckedCritical_ReopensOnlyOnWorsening_AndKeepsAckTimeline()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var engine = Engine(db);
        var incident = (await engine.EvaluateHeartRateSampleAsync("elder", "device", 185))!;
        incident.Status = IncidentStatus.Acknowledged;
        incident.AcknowledgedAt = DateTime.UtcNow;
        incident.AcknowledgedByCaregiverId = "caregiver";
        incident.AcknowledgedCriticalRuleCode = incident.LatestCriticalRuleCode;
        incident.AcknowledgedCriticalHeartRateBpm = incident.LatestCriticalHeartRateBpm;
        incident.ReminderCount = 2;
        incident.SlaBreachedAt = DateTime.UtcNow;
        incident.NextReminderAt = DateTime.UtcNow.AddMinutes(1);
        db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id, AlertCycleNumber = 1, EventType = "ACKNOWLEDGED",
            ActorCaregiverId = "caregiver", Description = "Caregiver accepted", RecordedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync();

        await engine.EvaluateHeartRateSampleAsync("elder", "device", 185);
        Assert.Equal(IncidentStatus.Acknowledged, incident.Status);
        Assert.Equal(1, incident.AlertCycleNumber);
        Assert.Equal(1, await db.NotificationOutboxes.CountAsync());

        await engine.EvaluateHeartRateSampleAsync("elder", "device", 195,
            measuredAtUtc: incident.AcknowledgedAt!.Value.AddSeconds(-1));
        Assert.Equal(IncidentStatus.Acknowledged, incident.Status);
        Assert.Equal(1, await db.NotificationOutboxes.CountAsync());

        await engine.EvaluateHeartRateSampleAsync("elder", "device", 190);
        Assert.Equal(IncidentStatus.Open, incident.Status);
        Assert.Equal(IncidentSeverity.Critical, incident.Severity);
        Assert.Equal(2, incident.AlertCycleNumber);
        Assert.Equal(0, incident.ReminderCount);
        Assert.Null(incident.SlaBreachedAt);
        Assert.Null(incident.NextReminderAt);
        Assert.Null(incident.AcknowledgedAt);
        Assert.Equal(185, incident.HeartRateBpm);
        Assert.Equal(190, incident.LatestCriticalHeartRateBpm);
        Assert.Equal(incident.AlertStartedAt!.Value.AddSeconds(60), incident.AlertDeadlineAt);
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());
        Assert.Contains(db.IncidentTimelineEvents, e => e.EventType == "ACKNOWLEDGED" &&
            e.ActorCaregiverId == "caregiver" && e.AlertCycleNumber == 1);
        Assert.Contains(db.IncidentTimelineEvents, e => e.EventType == "CLINICAL_REESCALATION" &&
            e.AlertCycleNumber == 2);
        await engine.EvaluateHeartRateSampleAsync("elder", "device", 190);
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());
    }

    [Fact]
    public async Task AckedFall_ReopensForNewCriticalHeartRate()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        db.Incidents.Add(new Incident
        {
            Id = "fall", ElderProfileId = "elder", TriggeredByDeviceId = "device",
            EmergencyType = EmergencyType.Fall, Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Acknowledged, AcknowledgedByCaregiverId = "caregiver"
        });
        await db.SaveChangesAsync();
        var result = await Engine(db).EvaluateHeartRateSampleAsync("elder", "device", 185);
        Assert.Equal("fall", result!.Id);
        Assert.Equal(IncidentStatus.Open, result.Status);
        Assert.Equal(2, result.AlertCycleNumber);
        Assert.Single(db.Incidents);
    }

    [Fact]
    public async Task SqlServer_MigrationAndCooldownPersistAcrossContexts()
    {
        var configured = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configured))
            return;

        var name = $"CareAI_Clinical_{Guid.NewGuid():N}";
        var master = new SqlConnectionStringBuilder(configured) { InitialCatalog = "master" };
        var test = new SqlConnectionStringBuilder(configured) { InitialCatalog = name };
        await using (var conn = new SqlConnection(master.ConnectionString))
        {
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"CREATE DATABASE [{name}]";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }
        try
        {
            await DatabaseMigrationHelper.InitializeDatabaseAsync(test.ConnectionString);
            await DatabaseMigrationHelper.InitializeDatabaseAsync(test.ConnectionString);
            await using (var first = NewSqlDb(test.ConnectionString))
            {
                await SeedAsync(first);
                var incident = await Engine(first).EvaluateHeartRateSampleAsync("elder", "device", 185);
                Assert.NotNull(incident);
            }
            await using (var second = NewSqlDb(test.ConnectionString))
            {
                var incident = await second.Incidents.SingleAsync();
                Assert.Equal(185, incident.LatestCriticalHeartRateBpm);
                Assert.Equal("HR_CRITICAL_HIGH", (await second.ClinicalRuleCooldowns.SingleAsync()).RuleCode);
                var controller = new IncidentsController(second,
                    new TelemetryEngine(second, NullLogger<TelemetryEngine>.Instance),
                    NullLogger<IncidentsController>.Instance)
                {
                    ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext
                    {
                        User = new ClaimsPrincipal(new ClaimsIdentity(
                            [new Claim(ClaimTypes.NameIdentifier, "caregiver")], "Test"))
                    } }
                };
                var ack = await controller.AcknowledgeIncident(incident.Id,
                    new AcknowledgeIncidentRequest("On my way", Convert.ToBase64String(incident.RowVersion!)),
                    CancellationToken.None);
                Assert.IsType<OkObjectResult>(ack);
                Assert.Equal(185, incident.AcknowledgedCriticalHeartRateBpm);
            }
            await using (var third = NewSqlDb(test.ConnectionString))
            {
                var incident = await Engine(third).EvaluateHeartRateSampleAsync("elder", "device", 190);
                Assert.Equal(IncidentStatus.Open, incident!.Status);
                Assert.Equal(2, incident.AlertCycleNumber);
                Assert.Equal(3, await third.NotificationOutboxes.CountAsync());
                Assert.Contains(third.IncidentTimelineEvents, e => e.EventType == "ACKNOWLEDGED" &&
                    e.ActorCaregiverId == "caregiver" && e.AlertCycleNumber == 1);
            }
        }
        finally
        {
            await using var conn = new SqlConnection(master.ConnectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"ALTER DATABASE [{name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{name}]";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }
    }

    private static ClinicalDiagnosticEngine Engine(CareAiDbContext db) =>
        new(db, NullLogger<ClinicalDiagnosticEngine>.Instance);

    private static CareAiDbContext NewMemoryDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Clinical_{Guid.NewGuid():N}").Options);

    private static CareAiDbContext NewSqlDb(string connection) => new(
        new DbContextOptionsBuilder<CareAiDbContext>().UseSqlServer(connection).Options);

    private static async Task SeedAsync(CareAiDbContext db)
    {
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder" });
        db.Caregivers.Add(new Caregiver
        {
            Id = "caregiver", FullName = "Test Caregiver", PhoneNumber = "123",
            Email = "caregiver@example.test", PasswordHash = "test"
        });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "link", ElderProfileId = "elder", CaregiverId = "caregiver", IsActive = true
        });
        db.CaregiverPushTokens.Add(new CaregiverPushToken
        {
            Id = "push", CaregiverId = "caregiver", PushToken = "test-token", IsActive = true
        });
        await db.SaveChangesAsync();
    }

    private static void AddSample(CareAiDbContext db, string metric, double value, DateTime at) =>
        db.HealthMeasurements.Add(new HealthMeasurement
        {
            ElderProfileId = "elder", DeviceId = "device", PacketId = Guid.NewGuid().ToString(),
            MetricType = metric, Value = value, Unit = metric == "STEPS" ? "steps" : "bpm", Timestamp = at
        });
}
