using System.Security.Cryptography;
using System.Text;
using CareAI.API.Controllers;
using CareAI.API.Middlewares;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class UrgentTelemetryTests
{
    [Theory]
    [InlineData(185)]
    [InlineData(35)]
    public async Task CriticalSample_CreatesOneIncidentAndOneOutbox_DespiteRetry(double heartRate)
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var controller = NewController(db, "device");
        var packet = new UrgentHeartRateRequest("urgent-heart-rate", heartRate, DateTime.UtcNow);

        var first = await controller.IngestUrgentHeartRate(packet, CancellationToken.None);
        Assert.Equal(201, Assert.IsType<ObjectResult>(first).StatusCode);
        var repeated = await controller.IngestUrgentHeartRate(packet, CancellationToken.None);
        Assert.IsType<OkObjectResult>(repeated);

        Assert.Equal(1, await db.ProcessedTelemetryLedgers.CountAsync());
        Assert.Equal(1, await db.HealthMeasurements.CountAsync(m => m.MetricType == "HEART_RATE"));
        Assert.Equal(1, await db.Incidents.CountAsync());
        Assert.Equal(1, await db.NotificationOutboxes.CountAsync());
        Assert.Equal(heartRate, (await db.Incidents.SingleAsync()).HeartRateBpm);
    }

    [Fact]
    public async Task StaleCriticalSample_IsStoredWithoutSoundingAnOldAlarm()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var controller = NewController(db, "device");

        var result = await controller.IngestUrgentHeartRate(
            new("old-packet", 185, DateTime.UtcNow.AddMinutes(-10)), CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);
        Assert.Equal(1, await db.HealthMeasurements.CountAsync());
        Assert.Equal(1, await db.ProcessedTelemetryLedgers.CountAsync());
        Assert.Empty(db.Incidents);
        Assert.Empty(db.NotificationOutboxes);
    }

    [Fact]
    public async Task SameMeasurementWithDifferentPacket_DoesNotEvaluateTwice()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var controller = NewController(db, "device");
        var at = DateTime.UtcNow;
        await controller.IngestUrgentHeartRate(new("packet-a", 185, at), CancellationToken.None);
        await controller.IngestUrgentHeartRate(new("packet-b", 185, at), CancellationToken.None);
        Assert.Equal(2, await db.ProcessedTelemetryLedgers.CountAsync());
        Assert.Single(db.HealthMeasurements);
        Assert.Single(db.Incidents);
        Assert.Single(db.NotificationOutboxes);
    }

    [Fact]
    public async Task BatchReplayAndStaleSample_DoNotCreateClinicalAlert()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var controller = NewController(db, "device");
        var stale = DateTime.UtcNow.AddMinutes(-10);
        var oldBatch = new TelemetryBatchRequest("old", [new("HEART_RATE", 185, "bpm", stale)]);
        await controller.IngestTelemetry(oldBatch, CancellationToken.None);
        Assert.Empty(db.Incidents);

        var at = DateTime.UtcNow;
        var current = new TelemetryBatchRequest("current", [new("HEART_RATE", 185, "bpm", at)]);
        await controller.IngestTelemetry(current, CancellationToken.None);
        await controller.IngestTelemetry(current with { BatchId = "replay" }, CancellationToken.None);
        Assert.Single(db.Incidents);
        Assert.Single(db.NotificationOutboxes);
        Assert.Equal(2, await db.HealthMeasurements.CountAsync());
    }

    [Fact]
    public async Task Endpoint_RejectsMissingDeviceAuthenticationAndNonCriticalValues()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        var controller = NewController(db, null);
        Assert.IsType<UnauthorizedObjectResult>(await controller.IngestUrgentHeartRate(
            new("packet", 185, DateTime.UtcNow), CancellationToken.None));

        controller.HttpContext.Items["ValidatedDeviceId"] = "device";
        Assert.IsType<BadRequestObjectResult>(await controller.IngestUrgentHeartRate(
            new("packet", 120, DateTime.UtcNow), CancellationToken.None));
        Assert.IsType<BadRequestObjectResult>(await controller.IngestUrgentHeartRate(
            new("packet", 185, DateTime.UtcNow.AddMinutes(5)), CancellationToken.None));
        Assert.Empty(db.ProcessedTelemetryLedgers);
    }

    [Fact]
    public async Task Middleware_AuthenticatesUrgentRouteWithDeviceHeaders()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        using var cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = 100 });
        var reachedEndpoint = false;
        var middleware = new DeviceTokenAuthMiddleware(
            _ => { reachedEndpoint = true; return Task.CompletedTask; },
            NullLogger<DeviceTokenAuthMiddleware>.Instance);
        var context = new DefaultHttpContext();
        context.Request.Path = "/api/v1/telemetry/urgent-heart-rate";
        context.Request.Headers["X-DeviceId"] = "device";
        context.Request.Headers["X-Device-Token"] = "test-device-token";

        await middleware.InvokeAsync(context, db, cache);

        Assert.True(reachedEndpoint);
        Assert.Equal("device", context.Items["ValidatedDeviceId"]);
    }

    [Fact]
    public async Task Middleware_AuthenticatesSyncWatchRouteWithDeviceHeaders()
    {
        await using var db = NewMemoryDb();
        await SeedAsync(db);
        using var cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = 100 });
        var reachedEndpoint = false;
        var middleware = new DeviceTokenAuthMiddleware(
            _ => { reachedEndpoint = true; return Task.CompletedTask; },
            NullLogger<DeviceTokenAuthMiddleware>.Instance);
        var context = new DefaultHttpContext();
        context.Request.Path = "/api/v1/devices/sync-watch";
        context.Request.Headers["X-DeviceId"] = "device";
        context.Request.Headers["X-Device-Token"] = "test-device-token";

        await middleware.InvokeAsync(context, db, cache);

        Assert.True(reachedEndpoint);
        Assert.Equal("device", context.Items["ValidatedDeviceId"]);
    }

    [Fact]
    public async Task SqlServer_SamePacketSentConcurrently_IsRecordedOnce()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configuredConnection))
            return;


        var databaseName = $"CareAI_Urgent_{Guid.NewGuid():N}";
        var master = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = "master" };
        var testDb = new SqlConnectionStringBuilder(configuredConnection) { InitialCatalog = databaseName };

        await using (var connection = new SqlConnection(master.ConnectionString))
        {
            await connection.OpenAsync();
            await using var create = connection.CreateCommand();
            create.CommandText = $"CREATE DATABASE [{databaseName}]";
            create.CommandTimeout = 120;
            await create.ExecuteNonQueryAsync();
        }

        try
        {
            await DatabaseMigrationHelper.InitializeDatabaseAsync(testDb.ConnectionString);
            await using (var seed = NewSqlDb(testDb.ConnectionString))
                await SeedAsync(seed);

            var packet = new UrgentHeartRateRequest("urgent-sql-185", 185, DateTime.UtcNow);
            await using var db1 = NewSqlDb(testDb.ConnectionString);
            await using var db2 = NewSqlDb(testDb.ConnectionString);
            var results = await Task.WhenAll(
                NewController(db1, "device").IngestUrgentHeartRate(packet, CancellationToken.None),
                NewController(db2, "device").IngestUrgentHeartRate(packet, CancellationToken.None));

            Assert.Single(results.OfType<OkObjectResult>());
            Assert.Single(results, r => r is ObjectResult o && o.StatusCode == 201);
            await using var verify = NewSqlDb(testDb.ConnectionString);
            Assert.Equal(1, await verify.ProcessedTelemetryLedgers.CountAsync());
            Assert.Equal(1, await verify.HealthMeasurements.CountAsync());
            Assert.Equal(1, await verify.Incidents.CountAsync());
            Assert.Equal(1, await verify.NotificationOutboxes.CountAsync());
        }
        finally
        {
            await using var connection = new SqlConnection(master.ConnectionString);
            await connection.OpenAsync();
            await using var drop = connection.CreateCommand();
            drop.CommandText = $"ALTER DATABASE [{databaseName}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{databaseName}]";
            drop.CommandTimeout = 120;
            await drop.ExecuteNonQueryAsync();
        }
    }

    private static CareAiDbContext NewMemoryDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Urgent_{Guid.NewGuid():N}").Options);

    private static CareAiDbContext NewSqlDb(string connectionString) => new(
        new DbContextOptionsBuilder<CareAiDbContext>().UseSqlServer(connectionString).Options);

    private static TelemetryController NewController(CareAiDbContext db, string? deviceId)
    {
        var clinical = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance);
        var controller = new TelemetryController(db,
            new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance),
            clinical,
            new UrgentTelemetryEngine(db, clinical),
            NullLogger<TelemetryController>.Instance);
        controller.ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() };
        if (deviceId != null) controller.HttpContext.Items["ValidatedDeviceId"] = deviceId;
        return controller;
    }

    private static async Task SeedAsync(CareAiDbContext db)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("test-device-token")))
            .ToLowerInvariant();
        db.ElderProfiles.Add(new ElderProfile
        {
            Id = "elder", FullName = "Test Elder", DateOfBirth = new DateTime(1945, 1, 1)
        });
        db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "device", ElderProfileId = "elder", DeviceTokenHash = hash,
            DeviceType = "Watch", IsActive = true
        });
        db.Caregivers.Add(new Caregiver
        {
            Id = "caregiver", FullName = "Caregiver", PhoneNumber = "123",
            Email = "caregiver@example.test", PasswordHash = "test-only"
        });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "link", ElderProfileId = "elder", CaregiverId = "caregiver", IsActive = true
        });
        db.CaregiverPushTokens.Add(new CaregiverPushToken
        {
            Id = "push", CaregiverId = "caregiver", PushToken = "test-push", IsActive = true
        });
        await db.SaveChangesAsync();
    }
}
