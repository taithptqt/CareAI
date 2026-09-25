using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging.Abstractions;

namespace CareAI.UnitTests;

public class Part2DataContractTests
{
    [Fact]
    public async Task SosSnapshot_IsPersistedAndDoesNotFollowLaterProfileOrTelemetryChanges()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder", HomeAddress = "Old address" });
        db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "device", ElderProfileId = "elder", DeviceTokenHash = "test-hash", DeviceType = "Watch"
        });
        await db.SaveChangesAsync();

        var engine = new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance);
        var measuredAt = DateTime.UtcNow.AddSeconds(-3);
        var first = new SosPacketRequest("packet-1", null, EmergencyType.ManualSos,
            "Critical", measuredAt, "10.7769, 106.7009",
            [new HealthSampleDto("HEART_RATE", 185, "bpm", measuredAt),
             new HealthSampleDto("SPO2", 93, "%", measuredAt)]);

        var result = await engine.ProcessFastLaneAsync("device", first);
        Assert.True(result.Success);
        Assert.NotNull(result.IncidentId);

        db.ElderProfiles.Single().HomeAddress = "New address";
        var followUp = first with
        {
            PacketId = "packet-2",
            GPSLocation = "11.0000, 107.0000",
            Samples = [new HealthSampleDto("HEART_RATE", 90, "bpm", DateTime.UtcNow)]
        };
        await engine.ProcessFastLaneAsync("device", followUp);

        var incident = await db.Incidents.Include(i => i.TimelineEvents).SingleAsync();
        Assert.Equal(185, incident.HeartRateBpm);
        Assert.Equal(93, incident.SpO2Percent);
        Assert.Equal(measuredAt, incident.VitalsMeasuredAt);
        Assert.Equal("10.7769, 106.7009", incident.GpsLocation);
        Assert.Equal("Old address", incident.HomeAddressSnapshot);
        Assert.Equal(1, incident.AlertCycleNumber);
        Assert.Equal(incident.AlertStartedAt!.Value.AddSeconds(60), incident.AlertDeadlineAt);

        incident.RowVersion = [1, 2, 3, 4];
        var dto = IncidentDtoMapper.ToResponse(incident, "Test Elder");
        Assert.Equal("AQIDBA==", dto.RowVersion);
        Assert.Equal("Old address", dto.Snapshot!.HomeAddress);
        Assert.Equal(185, dto.Snapshot.HeartRateBpm);
        Assert.Equal(1, dto.AlertState!.CycleNumber);
        Assert.Equal(2, dto.Timeline.Count);
    }

    [Fact]
    public async Task ClinicalIncident_CapturesHeartRateAndAddressWithSlaDeadline()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder", HomeAddress = "Clinic road" });
        await db.SaveChangesAsync();

        var engine = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance);
        var incident = await engine.EvaluateHeartRateSampleAsync("elder", "device", 185);

        Assert.NotNull(incident);
        Assert.Equal(IncidentSeverity.Critical, incident.Severity);
        Assert.Equal(185, incident.HeartRateBpm);
        Assert.Equal("Clinic road", incident.HomeAddressSnapshot);
        Assert.NotNull(incident.VitalsMeasuredAt);
        Assert.Equal(incident.AlertStartedAt!.Value.AddSeconds(60), incident.AlertDeadlineAt);
    }

    [Fact]
    public async Task NewSosAfterAck_OpensFreshSixtySecondAlertCycle()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder" });
        db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "device", ElderProfileId = "elder", DeviceTokenHash = "test-hash", DeviceType = "Watch"
        });
        await db.SaveChangesAsync();
        var engine = new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance);
        var first = await engine.ProcessFastLaneAsync("device",
            new SosPacketRequest("sos-1", null, EmergencyType.ManualSos, "Critical",
                DateTime.UtcNow, null, []));
        var incident = await db.Incidents.SingleAsync();
        Assert.True(first.Success);
        incident.Status = IncidentStatus.Acknowledged;
        incident.AcknowledgedAt = DateTime.UtcNow.AddSeconds(-1);
        incident.AcknowledgedByCaregiverId = "caregiver";
        incident.SlaBreachedAt = DateTime.UtcNow;
        incident.ReminderCount = 1;
        await db.SaveChangesAsync();

        var second = await engine.ProcessFastLaneAsync("device",
            new SosPacketRequest("sos-2", null, EmergencyType.ManualSos, "Critical",
                DateTime.UtcNow, null, []));
        Assert.True(second.Success);
        Assert.Equal(first.IncidentId, second.IncidentId);
        Assert.Equal(IncidentStatus.Open, incident.Status);
        Assert.Equal(2, incident.AlertCycleNumber);
        Assert.Equal(0, incident.ReminderCount);
        Assert.Null(incident.SlaBreachedAt);
        Assert.Equal(incident.AlertStartedAt!.Value.AddSeconds(60), incident.AlertDeadlineAt);
        Assert.Contains(db.IncidentTimelineEvents, e => e.EventType == "EMERGENCY_REESCALATION");
    }

    [Fact]
    public async Task CriticalSos_UpgradesExistingHighIncident_ForSlaMonitoring()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder" });
        db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "device", ElderProfileId = "elder", DeviceTokenHash = "test-hash", DeviceType = "Watch"
        });
        db.Incidents.Add(new Incident
        {
            Id = "existing", ElderProfileId = "elder", TriggeredByDeviceId = "device",
            EmergencyType = EmergencyType.Tachycardia,
            Severity = IncidentSeverity.High, Status = IncidentStatus.Open
        });
        await db.SaveChangesAsync();
        var engine = new TelemetryEngine(db, NullLogger<TelemetryEngine>.Instance);
        var result = await engine.ProcessFastLaneAsync("device",
            new SosPacketRequest("sos-critical", null, EmergencyType.ManualSos, "Critical",
                DateTime.UtcNow, null, []));
        Assert.True(result.Success);
        var incident = Assert.Single(db.Incidents);
        Assert.Equal("existing", incident.Id);
        Assert.Equal(IncidentSeverity.Critical, incident.Severity);
        Assert.Equal(incident.AlertStartedAt!.Value.AddSeconds(60), incident.AlertDeadlineAt);
        Assert.Contains(db.IncidentTimelineEvents, e => e.EventType == "EMERGENCY_ESCALATION");
    }

    [Fact]
    public async Task HomeAddressUpdate_RequiresCaregiverAccessAndDoesNotRewriteIncidentSnapshot()
    {
        await using var db = CreateDb();
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder", HomeAddress = "Original" });
        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = "link", ElderProfileId = "elder", CaregiverId = "allowed", IsActive = true
        });
        db.Incidents.Add(new Incident
        {
            Id = "incident", ElderProfileId = "elder", TriggeredByDeviceId = "device",
            EmergencyType = EmergencyType.ManualSos, HomeAddressSnapshot = "Original"
        });
        await db.SaveChangesAsync();

        var controller = new CaregiversController(db, NullLogger<CaregiversController>.Instance)
        {
            ControllerContext = new ControllerContext { HttpContext = ContextFor("stranger") }
        };
        var denied = await controller.UpdateElderHomeAddress("elder", new("Changed"), CancellationToken.None);
        Assert.Equal(StatusCodes.Status403Forbidden, Assert.IsType<ObjectResult>(denied).StatusCode);
        Assert.Equal("Original", db.ElderProfiles.Single().HomeAddress);

        controller.ControllerContext = new ControllerContext { HttpContext = ContextFor("allowed") };
        var updated = await controller.UpdateElderHomeAddress("elder", new("Changed"), CancellationToken.None);
        Assert.IsType<OkObjectResult>(updated);
        Assert.Equal("Changed", db.ElderProfiles.Single().HomeAddress);
        Assert.Equal("Original", db.Incidents.Single().HomeAddressSnapshot);
    }

    private static DefaultHttpContext ContextFor(string caregiverId)
    {
        var context = new DefaultHttpContext();
        context.User = new ClaimsPrincipal(new ClaimsIdentity(
            [new Claim(ClaimTypes.NameIdentifier, caregiverId)], "Test"));
        return context;
    }

    private static CareAiDbContext CreateDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Part2Contract_{Guid.NewGuid():N}").Options);
}
