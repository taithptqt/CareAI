using System.Security.Claims;
using CareAI.API.Controllers;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;

public class IncidentPhotoTests
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9];

    [Fact]
    public async Task DeviceUpload_IsIdempotentAndCannotReplacePhoto()
    {
        await using var db = CreateDb();
        await Seed(db);
        var controller = CreateController(db, deviceId: "device-1");
        Assert.IsType<ObjectResult>(await controller.Upload("incident-1", FormFile(Jpeg), DateTime.UtcNow, default));
        Assert.Single(await db.IncidentPhotos.ToListAsync());
        Assert.Single(await db.IncidentTimelineEvents.ToListAsync());
        Assert.IsType<OkObjectResult>(await controller.Upload("incident-1", FormFile(Jpeg), DateTime.UtcNow, default));
        Assert.IsType<ConflictObjectResult>(await controller.Upload("incident-1", FormFile([0xFF, 0xD8, 0x03, 0x04, 0xFF, 0xD9]), DateTime.UtcNow, default));
        Assert.Single(await db.IncidentTimelineEvents.ToListAsync());
    }

    [Fact]
    public async Task Photo_IsAccessibleOnlyToAuthorizedCaregiverAndOriginatingDevice()
    {
        await using var db = CreateDb();
        await Seed(db);
        Assert.IsType<ForbidResult>(await CreateController(db, deviceId: "device-2")
            .Upload("incident-1", FormFile(Jpeg), DateTime.UtcNow, default));
        Assert.IsType<UnauthorizedResult>(await CreateController(db)
            .Upload("incident-1", FormFile(Jpeg), DateTime.UtcNow, default));
        Assert.IsType<ObjectResult>(await CreateController(db, deviceId: "device-1")
            .Upload("incident-1", FormFile(Jpeg), DateTime.UtcNow, default));
        Assert.IsType<NotFoundResult>(await CreateController(db, caregiverId: "stranger").Get("incident-1", default));
        var image = Assert.IsType<FileContentResult>(await CreateController(db, caregiverId: "family").Get("incident-1", default));
        Assert.Equal(Jpeg, image.FileContents);
    }

    private static CareAiDbContext CreateDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"IncidentPhoto_{Guid.NewGuid():N}").Options);

    private static async Task Seed(CareAiDbContext db)
    {
        db.ElderProfiles.Add(new ElderProfile { Id = "elder-1", FullName = "Test elder" });
        db.DeviceRegistrations.AddRange(
            new DeviceRegistration { Id = "device-1", ElderProfileId = "elder-1", DeviceType = "SMARTPHONE_COMPANION" },
            new DeviceRegistration { Id = "device-2", ElderProfileId = "elder-2", DeviceType = "SMARTPHONE_COMPANION" });
        db.ElderCaregivers.Add(new ElderCaregiver { Id = "link-1", ElderProfileId = "elder-1", CaregiverId = "family", IsActive = true });
        db.Incidents.Add(new Incident { Id = "incident-1", ElderProfileId = "elder-1", TriggeredByDeviceId = "watch-1" });
        await db.SaveChangesAsync();
    }

    private static IncidentPhotosController CreateController(CareAiDbContext db, string? deviceId = null, string? caregiverId = null)
    {
        var context = new DefaultHttpContext();
        if (deviceId != null) context.Items["ValidatedDeviceId"] = deviceId;
        if (caregiverId != null)
            context.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, caregiverId)], "TestAuth"));
        return new IncidentPhotosController(db) { ControllerContext = new ControllerContext { HttpContext = context } };
    }

    private static FormFile FormFile(byte[] bytes)
    {
        var file = new FormFile(new MemoryStream(bytes), 0, bytes.Length, "photo", "scene.jpg");
        file.Headers = new HeaderDictionary();
        file.ContentType = "image/jpeg";
        return file;
    }
}
