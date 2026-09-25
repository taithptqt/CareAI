using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/incidents/{incidentId}/photo")]
public class IncidentPhotosController(CareAiDbContext db) : ControllerBase
{
    private const int MaxPhotoBytes = 1_000_000;

    [HttpPost]
    [Consumes("multipart/form-data")]
    [RequestSizeLimit(1_200_000)]
    public async Task<IActionResult> Upload(string incidentId, IFormFile photo,
        [FromForm] DateTime capturedAt, CancellationToken ct)
    {
        var deviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrWhiteSpace(deviceId)) return Unauthorized();
        var incident = await db.Incidents.AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == incidentId, ct);
        if (incident == null) return NotFound();
        // The watch may raise the incident while the elder's paired phone supplies the camera.
        var sameElderPhone = await db.DeviceRegistrations.AsNoTracking()
            .AnyAsync(d => d.Id == deviceId && d.ElderProfileId == incident.ElderProfileId &&
                d.IsActive && (d.DeviceType == "SMARTPHONE_COMPANION" || d.DeviceType == "CompanionPhone"), ct);
        if (!sameElderPhone) return Forbid();
        if (photo == null || photo.Length is < 4 or > MaxPhotoBytes ||
            !string.Equals(photo.ContentType, "image/jpeg", StringComparison.OrdinalIgnoreCase))
            return BadRequest(new { error = "Chỉ nhận ảnh JPEG tối đa 1 MB." });

        var at = capturedAt.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(capturedAt, DateTimeKind.Utc)
            : capturedAt.ToUniversalTime();
        if (at < incident.TriggeredAt.AddMinutes(-1) || at > DateTime.UtcNow.AddMinutes(1))
            return BadRequest(new { error = "Thời điểm chụp ảnh không hợp lệ." });

        await using var stream = photo.OpenReadStream();
        using var memory = new MemoryStream();
        await stream.CopyToAsync(memory, ct);
        var bytes = memory.ToArray();
        if (bytes.Length is < 4 or > MaxPhotoBytes ||
            bytes[0] != 0xFF || bytes[1] != 0xD8 ||
            bytes[^2] != 0xFF || bytes[^1] != 0xD9)
            return BadRequest(new { error = "Dữ liệu ảnh JPEG không hợp lệ." });

        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var existing = await db.IncidentPhotos.AsNoTracking()
            .FirstOrDefaultAsync(p => p.IncidentId == incidentId, ct);
        if (existing != null)
            return existing.Sha256 == hash ? Ok(new { status = "ALREADY_ATTACHED" }) :
                Conflict(new { error = "Sự cố đã có ảnh chứng cứ; không được thay thế." });

        var now = DateTime.UtcNow;
        db.IncidentPhotos.Add(new IncidentPhoto
        {
            IncidentId = incidentId, DeviceId = deviceId, JpegBytes = bytes,
            Sha256 = hash, CapturedAt = at, ReceivedAt = now
        });
        db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incidentId, AlertCycleNumber = incident.AlertCycleNumber,
            EventType = "PHOTO_ATTACHED", Description = "Thiết bị đã gửi ảnh hiện trường sự cố.",
            RecordedAt = now
        });
        var recipients = await db.ElderCaregivers.Where(ec => ec.ElderProfileId == incident.ElderProfileId && ec.IsActive)
            .Join(db.CaregiverPushTokens.Where(t => t.IsActive), ec => ec.CaregiverId,
                t => t.CaregiverId, (ec, t) => new { ec.CaregiverId, t.PushToken }).ToListAsync(ct);
        foreach (var recipient in recipients)
            db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incidentId, AlertCycleNumber = incident.AlertCycleNumber,
                RecipientCaregiverId = recipient.CaregiverId, PushToken = recipient.PushToken,
                Title = "Đã có ảnh sự cố", Body = "Mở CareAI để xem ảnh hiện trường của người thân.",
                DataPayloadJson = JsonSerializer.Serialize(new { incidentId, eventType = "PHOTO_AVAILABLE", siren = false }),
                Status = "PENDING", CreatedAt = now
            });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            db.ChangeTracker.Clear();
            var savedHash = await db.IncidentPhotos.AsNoTracking()
                .Where(p => p.IncidentId == incidentId).Select(p => p.Sha256).FirstOrDefaultAsync(ct);
            if (savedHash == hash) return Ok(new { status = "ALREADY_ATTACHED" });
            if (savedHash != null) return Conflict(new { error = "Sự cố đã có ảnh chứng cứ." });
            throw;
        }
        return StatusCode(StatusCodes.Status201Created, new { status = "ATTACHED" });
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> Get(string incidentId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrWhiteSpace(caregiverId)) return Unauthorized();
        var authorized = await db.Incidents.AsNoTracking()
            .Where(i => i.Id == incidentId)
            .Join(db.ElderCaregivers.Where(ec => ec.CaregiverId == caregiverId && ec.IsActive),
                i => i.ElderProfileId, ec => ec.ElderProfileId, (i, _) => i.Id)
            .AnyAsync(ct);
        if (!authorized) return NotFound();
        var image = await db.IncidentPhotos.AsNoTracking()
            .Where(p => p.IncidentId == incidentId).Select(p => p.JpegBytes).FirstOrDefaultAsync(ct);
        if (image == null) return NotFound();
        Response.Headers.CacheControl = "private, no-store";
        return File(image, "image/jpeg");
    }
}
