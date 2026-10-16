using System.Globalization;
using System.Text.Json;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/incidents/{incidentId}/location")]
public class IncidentLocationsController(CareAiDbContext db) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Attach(string incidentId,
        [FromBody] AttachIncidentLocationRequest request, CancellationToken ct)
    {
        var deviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrWhiteSpace(deviceId)) return Unauthorized();
        var incident = await db.Incidents.FirstOrDefaultAsync(i => i.Id == incidentId, ct);
        if (incident == null) return NotFound();
        var sameElderPhone = await db.DeviceRegistrations.AsNoTracking()
            .AnyAsync(d => d.Id == deviceId && d.ElderProfileId == incident.ElderProfileId &&
                d.IsActive && (d.DeviceType == "SMARTPHONE_COMPANION" || d.DeviceType == "CompanionPhone"), ct);
        if (!sameElderPhone) return Forbid();
        if (incident.Status == IncidentStatus.Resolved)
            return Conflict(new { error = "Sự cố đã đóng; không thể cập nhật vị trí hiện tại." });

        var parts = request.Coordinates?.Split(',', StringSplitOptions.TrimEntries);
        if (parts is not { Length: 2 } ||
            !double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var lat) ||
            !double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var lon) ||
            !double.IsFinite(lat) || !double.IsFinite(lon) ||
            lat is < -90 or > 90 || lon is < -180 or > 180)
            return BadRequest(new { error = "Tọa độ GPS không hợp lệ." });
        if (request.AccuracyMeters is { } accuracy &&
            (!double.IsFinite(accuracy) || accuracy is < 0 or > 100_000))
            return BadRequest(new { error = "Sai số GPS không hợp lệ." });
        var capturedAt = request.CapturedAt.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(request.CapturedAt, DateTimeKind.Utc)
            : request.CapturedAt.ToUniversalTime();
        var latestEmergencyAt = await db.IncidentTimelineEvents.AsNoTracking()
            .Where(t => t.IncidentId == incidentId &&
                (t.EventType == "TRIGGERED" || t.EventType == "REPEATED_EMERGENCY_SIGNAL"))
            .OrderByDescending(t => t.RecordedAt)
            .Select(t => (DateTime?)t.RecordedAt).FirstOrDefaultAsync(ct)
            ?? incident.TriggeredAt;
        if (capturedAt < latestEmergencyAt.AddMinutes(-1) ||
            capturedAt > latestEmergencyAt.AddMinutes(2) ||
            capturedAt > DateTime.UtcNow.AddSeconds(15))
            return BadRequest(new { error = "Vị trí không được đo gần thời điểm xảy ra sự cố." });

        var coordinates = $"{lat.ToString("F6", CultureInfo.InvariantCulture)}, {lon.ToString("F6", CultureInfo.InvariantCulture)}";
        if (incident.CurrentGpsMeasuredAt >= capturedAt)
            return incident.CurrentGpsLocation == coordinates
                ? Ok(new { status = "ALREADY_ATTACHED" })
                : Conflict(new { error = "Sự cố đã có tọa độ GPS mới hơn." });

        var now = DateTime.UtcNow;
        if (incident.GpsLocation == null &&
            capturedAt <= incident.TriggeredAt.AddMinutes(2))
            incident.GpsLocation = coordinates;
        incident.CurrentGpsLocation = coordinates;
        incident.CurrentGpsMeasuredAt = capturedAt;
        incident.CurrentGpsIsSimulated = request.IsSimulated;
        incident.CurrentGpsAccuracyMeters = request.AccuracyMeters;
        incident.UpdatedAt = now;
        db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incidentId, AlertCycleNumber = incident.AlertCycleNumber,
            EventType = "LOCATION_ATTACHED",
            Description = $"Điện thoại của ông/bà gửi {(request.IsSimulated ? "GPS mô phỏng" : "GPS")} lúc {capturedAt:O}: {coordinates}",
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
                Title = "Đã có vị trí GPS", Body = "Mở sự cố để xem vị trí hiện tại của người thân.",
                DataPayloadJson = JsonSerializer.Serialize(new { incidentId, eventType = "LOCATION_AVAILABLE", siren = false }),
                Status = "PENDING", CreatedAt = now
            });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Conflict(new { error = "Vị trí sự cố đã được cập nhật bởi yêu cầu khác." });
        }
        return Ok(new { status = "ATTACHED", coordinates });
    }
}
