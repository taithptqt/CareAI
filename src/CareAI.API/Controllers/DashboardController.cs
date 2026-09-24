using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/dashboard")]
[Authorize]
public class DashboardController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<DashboardController> _logger;

    public DashboardController(CareAiDbContext db, ILogger<DashboardController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Bảng điều khiển giám sát sức khỏe tổng hợp của Người cao tuổi (UC-15 / UC-16)
    /// </summary>
    [HttpGet("elder/{elderProfileId}")]
    [ProducesResponseType(typeof(ElderDashboardResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderDashboard(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        // BOLA Check
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        var elder = await _db.ElderProfiles
            .Include(e => e.Devices)
            .FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);

        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        var now = DateTime.UtcNow;
        var age = now.Year - elder.DateOfBirth.Year;
        if (elder.DateOfBirth.Date > now.AddYears(-age)) age--;

        // Trạng thái thiết bị
        var activeDevices = elder.Devices.Where(d => d.IsActive).ToList();
        var isOnline = activeDevices.Any(d => d.LastHeartbeat >= now.AddMinutes(-15));
        var deviceStatus = isOnline ? "ONLINE" : "OFFLINE";
        var lastSyncedAt = activeDevices.Count > 0 ? (DateTime?)activeDevices.Max(d => d.LastHeartbeat) : null;

        // Chỉ số sinh hiệu mới nhất
        var latestHr = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "HEART_RATE")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        var latestSpo2 = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "SPO2")
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        var latestBp = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && (m.MetricType == "BLOOD_PRESSURE" || m.MetricType == "BP_SYSTOLIC"))
            .OrderByDescending(m => m.Timestamp)
            .FirstOrDefaultAsync(ct);

        // Số bước chân hôm nay
        var todayStart = DateTime.UtcNow.Date;
        var todaySteps = (int)await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == elderProfileId && m.MetricType == "STEPS" && m.Timestamp >= todayStart)
            .SumAsync(m => m.Value, ct);

        // Sự cố đang mở
        var activeIncident = await _db.Incidents
            .Include(i => i.TimelineEvents)
            .FirstOrDefaultAsync(i => i.ElderProfileId == elderProfileId && 
                                     (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        // Badge màu sắc tổng thể
        string badgeColor = "GREEN";
        if (activeIncident != null)
        {
            badgeColor = activeIncident.Severity == IncidentSeverity.Critical ? "RED" : "YELLOW";
        }
        else if (latestHr != null && (latestHr.Value > 100 || latestHr.Value < 50))
        {
            badgeColor = "YELLOW";
        }

        var response = new ElderDashboardResponse(
            elder.Id,
            elder.FullName,
            age,
            badgeColor,
            deviceStatus,
            latestHr != null ? new VitalSignDto(latestHr.MetricType, latestHr.Value, latestHr.Unit, latestHr.Timestamp, latestHr.Value > 100 || latestHr.Value < 50 ? "YELLOW" : "GREEN") : null,
            latestBp != null ? new VitalSignDto(latestBp.MetricType, latestBp.Value, latestBp.Unit, latestBp.Timestamp, "GREEN") : null,
            latestSpo2 != null ? new VitalSignDto(latestSpo2.MetricType, latestSpo2.Value, latestSpo2.Unit, latestSpo2.Timestamp, latestSpo2.Value < 95 ? "YELLOW" : "GREEN") : null,
            todaySteps,
            StepGoal: 6000,
            LastKnownGpsLocation: null,
            lastSyncedAt,
            activeIncident != null ? new IncidentResponseDto(
                activeIncident.Id,
                activeIncident.ElderProfileId,
                elder.FullName,
                activeIncident.TriggeredByDeviceId,
                activeIncident.EmergencyType,
                activeIncident.Severity.ToString(),
                activeIncident.Status.ToString(),
                activeIncident.TriggeredAt,
                activeIncident.AcknowledgedAt,
                activeIncident.AcknowledgedByCaregiverId,
                activeIncident.ResolvedAt,
                activeIncident.ResolvedByCaregiverId,
                activeIncident.ResolutionNotes,
                activeIncident.TimelineEvents.OrderBy(t => t.RecordedAt).Select(t => new IncidentTimelineDto(t.EventType, t.Description, t.RecordedAt)).ToList()
            ) : null
        );

        return Ok(response);
    }
}
