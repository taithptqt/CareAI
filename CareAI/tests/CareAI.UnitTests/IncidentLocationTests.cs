using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;

public class IncidentLocationTests
{
    [Fact]
    public async Task CurrentPhoneLocation_IsAttachedOnceAndVisibleOnIncident()
    {
        await using var db = CreateDb();
        await Seed(db);
        var controller = CreateController(db, "phone-1");
        var measuredAt = DateTime.UtcNow;
        var request = new AttachIncidentLocationRequest("10.762622, 106.660172", measuredAt,
            IsSimulated: true, AccuracyMeters: 5);
        Assert.IsType<OkObjectResult>(await controller.Attach("incident-1", request, default));
        Assert.Equal("10.762622, 106.660172", (await db.Incidents.FindAsync("incident-1"))!.GpsLocation);
        Assert.True((await db.Incidents.FindAsync("incident-1"))!.CurrentGpsIsSimulated);
        Assert.Equal(5, (await db.Incidents.FindAsync("incident-1"))!.CurrentGpsAccuracyMeters);
        Assert.Single(await db.IncidentTimelineEvents.ToListAsync());
        Assert.IsType<OkObjectResult>(await controller.Attach("incident-1", request, default));
        Assert.IsType<ConflictObjectResult>(await controller.Attach("incident-1",
            new AttachIncidentLocationRequest("10.800000, 106.700000", measuredAt), default));
        Assert.Single(await db.IncidentTimelineEvents.ToListAsync());
    }

    [Fact]
    public async Task Location_RejectsOtherElderAndStaleOrInvalidFix()
    {
        await using var db = CreateDb();
        await Seed(db);
        Assert.IsType<ForbidResult>(await CreateController(db, "phone-other").Attach("incident-1",
            new AttachIncidentLocationRequest("10.762622, 106.660172", DateTime.UtcNow), default));
        var controller = CreateController(db, "phone-1");
        Assert.IsType<BadRequestObjectResult>(await controller.Attach("incident-1",
            new AttachIncidentLocationRequest("999, 106", DateTime.UtcNow), default));
        Assert.IsType<BadRequestObjectResult>(await controller.Attach("incident-1",
            new AttachIncidentLocationRequest("10.762622, 106.660172", DateTime.UtcNow.AddMinutes(-5)), default));
        Assert.Null((await db.Incidents.FindAsync("incident-1"))!.GpsLocation);
    }

    [Fact]
    public async Task RepeatedEmergency_RefreshesCurrentGpsWithoutChangingOriginalSnapshot()
    {
        await using var db = CreateDb();
        await Seed(db);
        var incident = (await db.Incidents.FindAsync("incident-1"))!;
        incident.TriggeredAt = DateTime.UtcNow.AddMinutes(-10);
        incident.GpsLocation = "10.000000, 106.000000";
        incident.CurrentGpsLocation = incident.GpsLocation;
        incident.CurrentGpsMeasuredAt = incident.TriggeredAt;
        db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id, EventType = "REPEATED_EMERGENCY_SIGNAL",
            Description = "New fall", RecordedAt = DateTime.UtcNow
        });
        await db.SaveChangesAsync();
        var result = await CreateController(db, "phone-1").Attach("incident-1",
            new AttachIncidentLocationRequest("11.000000, 107.000000", DateTime.UtcNow), default);
        Assert.IsType<OkObjectResult>(result);
        Assert.Equal("10.000000, 106.000000", incident.GpsLocation);
        Assert.Equal("11.000000, 107.000000", incident.CurrentGpsLocation);
    }

    private static CareAiDbContext CreateDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"IncidentLocation_{Guid.NewGuid():N}").Options);

    private static async Task Seed(CareAiDbContext db)
    {
        db.ElderProfiles.Add(new ElderProfile { Id = "elder-1", FullName = "Test elder" });
        db.DeviceRegistrations.AddRange(
            new DeviceRegistration { Id = "phone-1", ElderProfileId = "elder-1", DeviceType = "SMARTPHONE_COMPANION" },
            new DeviceRegistration { Id = "phone-other", ElderProfileId = "elder-other", DeviceType = "SMARTPHONE_COMPANION" });
        db.Incidents.Add(new Incident { Id = "incident-1", ElderProfileId = "elder-1", TriggeredByDeviceId = "watch-1" });
        await db.SaveChangesAsync();
    }

    private static IncidentLocationsController CreateController(CareAiDbContext db, string deviceId)
    {
        var context = new DefaultHttpContext();
        context.Items["ValidatedDeviceId"] = deviceId;
        return new IncidentLocationsController(db) { ControllerContext = new ControllerContext { HttpContext = context } };
    }
}
