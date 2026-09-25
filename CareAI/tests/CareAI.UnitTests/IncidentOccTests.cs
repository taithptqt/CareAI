using System.Security.Claims;
using System.Text.Json;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class IncidentOccTests
{
    [Fact]
    public async Task Validation_RejectsMissingVersionBlankResolutionAndUnauthorizedCaregiver()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase($"OccValidation_{Guid.NewGuid():N}").Options);
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Elder" });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "link", ElderProfileId = "elder", CaregiverId = "allowed", IsActive = true
        });
        db.Incidents.Add(new Incident
        {
            Id = "incident", ElderProfileId = "elder", TriggeredByDeviceId = "device",
            EmergencyType = "FALL", Status = IncidentStatus.Open,
            RowVersion = [1, 2, 3, 4, 5, 6, 7, 8]
        });
        await db.SaveChangesAsync();

        var stranger = Controller(db, "stranger");
        Assert.Equal(403, Assert.IsType<ObjectResult>(await stranger.AcknowledgeIncident(
            "incident", new("help", null), CancellationToken.None)).StatusCode);

        var allowed = Controller(db, "allowed");
        Assert.IsType<BadRequestObjectResult>(await allowed.AcknowledgeIncident(
            "incident", new("help", null), CancellationToken.None));
        Assert.IsType<BadRequestObjectResult>(await allowed.AcknowledgeIncident(
            "incident", new("help", "not-base64"), CancellationToken.None));
        Assert.IsType<ConflictObjectResult>(await allowed.ResolveIncident(
            "incident", new("notes", Convert.ToBase64String([1, 2, 3, 4, 5, 6, 7, 8])), CancellationToken.None));

        db.Incidents.Single().Status = IncidentStatus.Acknowledged;
        await db.SaveChangesAsync();
        Assert.Equal(403, Assert.IsType<ObjectResult>(await stranger.ResolveIncident(
            "incident", new("Finished", null), CancellationToken.None)).StatusCode);
        Assert.IsType<BadRequestObjectResult>(await allowed.ResolveIncident(
            "incident", new("   ", Convert.ToBase64String([1, 2, 3, 4, 5, 6, 7, 8])), CancellationToken.None));
        Assert.Empty(db.IncidentTimelineEvents);
        Assert.Empty(db.NotificationOutboxes);
    }

    [Fact]
    public async Task SqlServer_ConcurrentAcknowledgement_HasOneWinnerAndOneConflict()
    {
        var configuredConnection = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configuredConnection))
            return;


        var databaseName = $"CareAI_Occ_{Guid.NewGuid():N}";
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
            {
                seed.ElderProfiles.Add(new ElderProfile
                {
                    Id = "elder", FullName = "Test Elder", DateOfBirth = new DateTime(1945, 1, 1)
                });
                foreach (var id in new[] { "first", "second" })
                {
                    seed.Caregivers.Add(new Caregiver
                    {
                        Id = id, FullName = $"Caregiver {id}", PhoneNumber = id,
                        Email = $"{id}@example.test", PasswordHash = "test-only"
                    });
                    seed.ElderCaregivers.Add(new ElderCaregiver
                    {
                        Id = $"link-{id}", ElderProfileId = "elder", CaregiverId = id, IsActive = true
                    });
                    seed.CaregiverPushTokens.Add(new CaregiverPushToken
                    {
                        Id = $"token-{id}", CaregiverId = id, PushToken = $"push-{id}", IsActive = true
                    });
                }
                seed.Incidents.Add(new Incident
                {
                    Id = "incident", ElderProfileId = "elder", TriggeredByDeviceId = "device",
                    EmergencyType = "FALL", Severity = IncidentSeverity.Critical,
                    Status = IncidentStatus.Open, TriggeredAt = DateTime.UtcNow
                });
                await seed.SaveChangesAsync();
            }

            await using var db1 = NewSqlDb(testDb.ConnectionString);
            await using var db2 = NewSqlDb(testDb.ConnectionString);
            var version = await db1.Incidents.AsNoTracking()
                .Where(i => i.Id == "incident")
                .Select(i => i.RowVersion)
                .SingleAsync();
            Assert.NotNull(version);
            Assert.Equal(8, version.Length);
            var token = Convert.ToBase64String(version);

            var first = Controller(db1, "first").AcknowledgeIncident(
                "incident", new("Coming", token), CancellationToken.None);
            var second = Controller(db2, "second").AcknowledgeIncident(
                "incident", new("Coming", token), CancellationToken.None);
            var outcomes = await Task.WhenAll(first, second);
            Assert.Single(outcomes.OfType<OkObjectResult>());
            var conflict = Assert.Single(outcomes.OfType<ConflictObjectResult>());

            await using var verify = NewSqlDb(testDb.ConnectionString);
            var current = await verify.Incidents.AsNoTracking().SingleAsync();
            Assert.Equal(IncidentStatus.Acknowledged, current.Status);
            Assert.NotEqual(token, Convert.ToBase64String(current.RowVersion!));
            using (var body = JsonDocument.Parse(JsonSerializer.Serialize(conflict.Value)))
            {
                Assert.Equal("INCIDENT_CONFLICT", body.RootElement.GetProperty("code").GetString());
                Assert.Equal(current.AcknowledgedByCaregiverId,
                    body.RootElement.GetProperty("acknowledgedByCaregiverId").GetString());
                Assert.False(string.IsNullOrWhiteSpace(body.RootElement.GetProperty("acknowledgedByName").GetString()));
            }
            Assert.Equal(1, await verify.IncidentTimelineEvents.CountAsync(t => t.EventType == "ACKNOWLEDGED"));
            Assert.Equal(2, await verify.NotificationOutboxes.CountAsync(n => n.DataPayloadJson.Contains("ACKNOWLEDGED")));

            var resolver = Controller(verify, "first");
            Assert.IsType<ConflictObjectResult>(await resolver.ResolveIncident(
                "incident", new("Checked and safe", token), CancellationToken.None));
            Assert.IsType<BadRequestObjectResult>(await resolver.ResolveIncident(
                "incident", new(" ", Convert.ToBase64String(current.RowVersion!)), CancellationToken.None));
            Assert.IsType<OkObjectResult>(await resolver.ResolveIncident(
                "incident", new("Checked and safe", Convert.ToBase64String(current.RowVersion!)), CancellationToken.None));
            Assert.IsType<ConflictObjectResult>(await resolver.ResolveIncident(
                "incident", new("Duplicate", Convert.ToBase64String(current.RowVersion!)), CancellationToken.None));
            Assert.Equal(1, await verify.IncidentTimelineEvents.CountAsync(t => t.EventType == "RESOLVED"));
            Assert.Equal(2, await verify.NotificationOutboxes.CountAsync(n => n.DataPayloadJson.Contains("RESOLVED")));
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

    private static CareAiDbContext NewSqlDb(string connectionString) => new(
        new DbContextOptionsBuilder<CareAiDbContext>().UseSqlServer(connectionString).Options);

    private static IncidentsController Controller(CareAiDbContext db, string caregiverId)
    {
        var controller = new IncidentsController(db,
            new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance),
            NullLogger<IncidentsController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(
                    [new Claim(ClaimTypes.NameIdentifier, caregiverId)], "Test"))
            }
        };
        return controller;
    }
}
