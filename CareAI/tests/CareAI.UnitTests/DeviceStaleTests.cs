using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class DeviceStaleTests
{
    [Fact]
    public async Task OneOfTwoDevicesOnline_PreventsOfflineIncident_AtFiveMinuteBoundary()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now);
        var devices = await db.DeviceRegistrations.OrderBy(d => d.Id).ToListAsync();
        devices[0].LastHeartbeat = now.AddMinutes(-6);
        devices[1].LastHeartbeat = now.AddMinutes(-5);
        await db.SaveChangesAsync();

        await Engine(db).ScanAsync(now);
        Assert.Empty(db.Incidents);
        Assert.Empty(db.NotificationOutboxes);

        devices[1].LastHeartbeat = now.AddMinutes(-5).AddTicks(-1);
        await db.SaveChangesAsync();
        await Engine(db).ScanAsync(now);
        var incident = Assert.Single(db.Incidents);
        Assert.Equal(EmergencyType.StaleOffline, incident.EmergencyType);
        Assert.Equal(IncidentSeverity.Medium, incident.Severity);
        Assert.Equal(IncidentStatus.Open, incident.Status);
        Assert.Equal(now, incident.ConnectivityLostAt);
        Assert.Single(db.NotificationOutboxes);
        Assert.DoesNotContain("\"siren\":true", db.NotificationOutboxes.Single().DataPayloadJson);
        await Engine(db).ScanAsync(now.AddSeconds(60));
        Assert.Single(db.Incidents);
        Assert.Single(db.NotificationOutboxes);
        Assert.Single(db.IncidentTimelineEvents);
    }

    [Theory]
    [InlineData(EmergencyType.Fall)]
    [InlineData(EmergencyType.ManualSos)]
    public async Task ActiveEmergency_SuppressesOfflineIncident_AndRecordsOneTimelineEvent(string emergencyType)
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now.AddMinutes(-6));
        db.Incidents.Add(new Incident
        {
            Id = "emergency", ElderProfileId = "elder", TriggeredByDeviceId = "device-a",
            EmergencyType = emergencyType, Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Acknowledged
        });
        await db.SaveChangesAsync();

        await Engine(db).ScanAsync(now);
        await Engine(db).ScanAsync(now.AddSeconds(60));
        var incident = Assert.Single(db.Incidents);
        Assert.Equal("emergency", incident.Id);
        Assert.Equal(IncidentStatus.Acknowledged, incident.Status);
        Assert.Single(db.IncidentTimelineEvents.Where(t => t.EventType == "DEVICE_STALE_SUPPRESSED"));
        Assert.Empty(db.NotificationOutboxes);

        db.DeviceRegistrations.Single(d => d.Id == "device-b").LastHeartbeat = now.AddMinutes(1);
        await db.SaveChangesAsync();
        await Engine(db).ScanAsync(now.AddMinutes(1));
        Assert.Null(incident.ConnectivityLostAt);
        Assert.Single(db.IncidentTimelineEvents.Where(t => t.EventType == "DEVICE_RECONNECTED"));
        Assert.Equal(IncidentStatus.Acknowledged, incident.Status);
    }

    [Fact]
    public async Task Reconnection_AutoResolvesOnlyOfflineIncident_WithReasonAndTimeline()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now.AddMinutes(-6));
        await Engine(db).ScanAsync(now);
        var incident = Assert.Single(db.Incidents);
        db.DeviceRegistrations.Single(d => d.Id == "device-b").LastHeartbeat = now.AddSeconds(10);
        await db.SaveChangesAsync();

        await Engine(db).ScanAsync(now.AddMinutes(1));
        Assert.Equal(IncidentStatus.Resolved, incident.Status);
        Assert.Equal(now.AddMinutes(1), incident.ResolvedAt);
        Assert.False(string.IsNullOrWhiteSpace(incident.ResolutionNotes));
        Assert.Null(incident.ConnectivityLostAt);
        Assert.Single(db.IncidentTimelineEvents.Where(t => t.EventType == "AUTO_RESOLVED"));
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());
        await Engine(db).ScanAsync(now.AddMinutes(2));
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());
    }

    [Fact]
    public async Task OtherActiveIncident_ReceivesConnectivityEvidence_WithoutUniqueIndexConflict()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now.AddMinutes(-6));
        db.Incidents.Add(new Incident
        {
            Id = "clinical", ElderProfileId = "elder", TriggeredByDeviceId = "device-a",
            EmergencyType = EmergencyType.Tachycardia, Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Open
        });
        await db.SaveChangesAsync();
        await Engine(db).ScanAsync(now);
        Assert.Single(db.Incidents);
        Assert.Single(db.IncidentTimelineEvents.Where(t => t.EventType == "DEVICE_STALE"));
    }

    [Fact]
    public async Task InactiveDevice_DoesNotCountTowardAllDevicesOffline()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now.AddMinutes(-6));
        var inactive = db.DeviceRegistrations.Single(d => d.Id == "device-b");
        inactive.IsActive = false;
        inactive.LastHeartbeat = now;
        await db.SaveChangesAsync();
        await Engine(db).ScanAsync(now);
        Assert.Single(db.Incidents);
    }

    [Fact]
    public async Task SqlServer_ConcurrentScans_KeepOneActiveIncident_AndRecoveryPersists()
    {
        var configured = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configured))
            throw SkipException.ForSkip("Set CAREAI_TEST_SQL_CONNECTION_STRING for SQL Server integration test.");
        var name = $"CareAI_Watchdog_{Guid.NewGuid():N}";
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
            var now = DateTime.UtcNow;
            await using (var seed = NewSqlDb(test.ConnectionString)) await SeedAsync(seed, now.AddMinutes(-6));
            await using var first = NewSqlDb(test.ConnectionString);
            await using var second = NewSqlDb(test.ConnectionString);
            await Task.WhenAll(Engine(first).ScanAsync(now), Engine(second).ScanAsync(now));
            await using (var verify = NewSqlDb(test.ConnectionString))
            {
                Assert.Equal(1, await verify.Incidents.CountAsync(i => i.Status == IncidentStatus.Open));
                Assert.Single(verify.NotificationOutboxes);
                verify.DeviceRegistrations.Single(d => d.Id == "device-b").LastHeartbeat = now.AddSeconds(1);
                await verify.SaveChangesAsync();
            }
            await using (var recover = NewSqlDb(test.ConnectionString))
            {
                await Engine(recover).ScanAsync(now.AddMinutes(1));
                var incident = await recover.Incidents.SingleAsync();
                Assert.Equal(IncidentStatus.Resolved, incident.Status);
                Assert.Contains(recover.IncidentTimelineEvents, e => e.EventType == "AUTO_RESOLVED");
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

    private static DeviceStaleEngine Engine(CareAiDbContext db) =>
        new(db, NullLogger<DeviceStaleEngine>.Instance);

    private static CareAiDbContext NewMemoryDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Watchdog_{Guid.NewGuid():N}").Options);

    private static CareAiDbContext NewSqlDb(string connection) => new(
        new DbContextOptionsBuilder<CareAiDbContext>().UseSqlServer(connection).Options);

    private static async Task SeedAsync(CareAiDbContext db, DateTime heartbeat)
    {
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder", HomeAddress = "Test address" });
        db.DeviceRegistrations.AddRange(
            new DeviceRegistration { Id = "device-a", ElderProfileId = "elder", DeviceType = "Watch",
                DeviceTokenHash = "a", LastHeartbeat = heartbeat },
            new DeviceRegistration { Id = "device-b", ElderProfileId = "elder", DeviceType = "Phone",
                DeviceTokenHash = "b", LastHeartbeat = heartbeat });
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
}
