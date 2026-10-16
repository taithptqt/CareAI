using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using CareAI.Infrastructure.Notifications;
using Microsoft.Extensions.Options;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/incidents")]
public class IncidentsController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly AlertingOptions _alertingOptions;
    private readonly ILogger<IncidentsController> _logger;

    public IncidentsController(
        CareAiDbContext db,
        TelemetryEngine telemetryEngine,
        ILogger<IncidentsController> logger,
        IOptions<AlertingOptions>? alertingOptions = null)
    {
        _db = db;
        _telemetryEngine = telemetryEngine;
        _logger = logger;
        _alertingOptions = alertingOptions?.Value ?? new AlertingOptions();
    }

    /// <summary>
    /// Kích hoạt Nút bấm SOS / Phát hiện Té ngã Fast-Lane: Idempotent với PacketId do client gửi lên.
    /// </summary>
    [HttpPost("sos")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> TriggerFastLaneSos([FromBody] SosPacketRequest request, CancellationToken ct)
    {
        var validatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(validatedDeviceId))
        {
            return Unauthorized(new { error = "Thiếu xác thực thiết bị." });
        }
        if (request.GPSLocation?.Trim().Length > 100)
            return BadRequest(new { error = "Vị trí GPS không được vượt quá 100 ký tự." });
        if (request.GpsAccuracyMeters is { } accuracy &&
            (!double.IsFinite(accuracy) || accuracy is < 0 or > 100_000))
            return BadRequest(new { error = "Sai số GPS không hợp lệ." });

        // BẢO VỆ CHỐNG GIẢ MẠO THIẾT BỊ (ANTI-DEVICE-IMPERSONATION / BOLA):
        var effectiveDeviceId = validatedDeviceId;

        // Chuẩn hóa loại cấp cứu
        var emergencyType = string.IsNullOrWhiteSpace(request.EmergencyType) ? "MANUAL_SOS" : request.EmergencyType.ToUpperInvariant();

        var (success, incidentId, message) = await _telemetryEngine.ProcessFastLaneAsync(effectiveDeviceId, request, ct);

        if (!success)
        {
            return BadRequest(new { error = message });
        }

        if (incidentId == null)
        {
            return Ok(new
            {
                status = "ALREADY_PROCESSED",
                packetId = request.PacketId,
                incidentId,
                message
            });
        }

        return StatusCode(StatusCodes.Status201Created, new
        {
            status = "SOS_TRIGGERED",
            incidentId,
            message
        });
    }

    /// <summary>
    /// Danh sách Sự cố Đang mở / Đã tiếp nhận của các cụ mà Người thân này được phân quyền chăm sóc
    /// </summary>
    [HttpGet("active")]
    [Authorize]
    [ProducesResponseType(typeof(List<IncidentResponseDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetActiveIncidents(CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var allowedElderIds = await _db.ElderCaregivers
            .Where(ec => ec.CaregiverId == caregiverId && ec.IsActive)
            .Select(ec => ec.ElderProfileId)
            .ToListAsync(ct);

        var incidents = await _db.Incidents
            .AsNoTracking()
            .Include(i => i.ElderProfile)
            .Include(i => i.TimelineEvents)
            .Where(i => allowedElderIds.Contains(i.ElderProfileId) &&
                       (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged))
            .OrderByDescending(i => i.TriggeredAt)
            .ToListAsync(ct);

        var result = incidents.Select(i => IncidentDtoMapper.ToResponse(
            i, i.ElderProfile?.FullName ?? "N/A")).ToList();

        return Ok(result);
    }

    /// <summary>
    /// Lịch sử sự cố của Người cao tuổi có BOLA, phân trang ổn định và bộ lọc (Task 8 / UC-08 / UC-16)
    /// </summary>
    [HttpGet("/api/v1/elders/{elderProfileId}/incidents")]
    [HttpGet("elder/{elderProfileId}/history")]
    [Authorize]
    [ProducesResponseType(typeof(PagedResult<IncidentResponseDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderIncidentHistory(
        string elderProfileId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? emergencyType = null,
        [FromQuery] string? severity = null,
        [FromQuery] string? status = null,
        [FromQuery] DateTime? fromUtc = null,
        [FromQuery] DateTime? toUtc = null,
        CancellationToken ct = default)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var elder = await _db.ElderProfiles.AsNoTracking()
            .FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);
        if (elder == null)
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });

        // BOLA Check
        var isAuthorized = await _db.ElderCaregivers.AsNoTracking()
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin người cao tuổi này." });
        }

        if (page < 1) page = 1;
        if (pageSize < 1) pageSize = 20;
        if (pageSize > 100) pageSize = 100;

        var query = _db.Incidents.AsNoTracking()
            .Where(i => i.ElderProfileId == elderProfileId);

        if (!string.IsNullOrWhiteSpace(emergencyType))
        {
            var trimmedType = emergencyType.Trim().ToUpperInvariant();
            query = query.Where(i => i.EmergencyType == trimmedType);
        }

        if (!string.IsNullOrWhiteSpace(severity) && Enum.TryParse<IncidentSeverity>(severity.Trim(), true, out var parsedSeverity))
        {
            query = query.Where(i => i.Severity == parsedSeverity);
        }

        if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<IncidentStatus>(status.Trim(), true, out var parsedStatus))
        {
            query = query.Where(i => i.Status == parsedStatus);
        }

        if (fromUtc.HasValue)
        {
            query = query.Where(i => i.TriggeredAt >= fromUtc.Value);
        }

        if (toUtc.HasValue)
        {
            query = query.Where(i => i.TriggeredAt <= toUtc.Value);
        }

        var totalCount = await query.CountAsync(ct);
        var totalPages = (int)Math.Ceiling(totalCount / (double)pageSize);

        var incidents = await query
            .Include(i => i.ElderProfile)
            .Include(i => i.TimelineEvents)
            .OrderByDescending(i => i.TriggeredAt)
            .ThenByDescending(i => i.Id)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync(ct);

        var items = incidents.Select(i => IncidentDtoMapper.ToResponse(i, elder.FullName)).ToList();

        return Ok(new PagedResult<IncidentResponseDto>(items, page, pageSize, totalCount, totalPages));
    }

    /// <summary>
    /// Chi tiết sự cố kèm Timeline và Chuỗi nhịp tim T-15...T+15 phút quanh sự cố
    /// </summary>
    [HttpGet("{id}")]
    [Authorize]
    [ProducesResponseType(typeof(IncidentResponseDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetIncident(string id, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        var incident = await _db.Incidents.AsNoTracking()
            .Include(i => i.ElderProfile)
            .Include(i => i.TimelineEvents)
            .FirstOrDefaultAsync(i => i.Id == id, ct);
        if (incident == null) return NotFound();

        var allowed = await _db.ElderCaregivers.AnyAsync(ec =>
            ec.CaregiverId == caregiverId && ec.ElderProfileId == incident.ElderProfileId && ec.IsActive, ct);
        if (!allowed) return Forbid();

        // Chuỗi nhịp tim hoặc SpO2 T-15...T+15 phút quanh mốc xảy ra sự cố (Task 8 / Bước 8)
        var windowStart = incident.TriggeredAt.AddMinutes(-15);
        var windowEnd = incident.TriggeredAt.AddMinutes(15);
        var metricType = incident.EmergencyType == EmergencyType.LowOxygen ? "SPO2" : "HEART_RATE";
        var hrSamples = await _db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == incident.ElderProfileId
                     && m.MetricType == metricType
                     && m.Timestamp >= windowStart
                     && m.Timestamp <= windowEnd)
            .OrderBy(m => m.Timestamp)
            .Select(m => new HeartRateSampleDto(m.Timestamp, m.Value, m.Unit, m.DeviceId))
            .ToListAsync(ct);

        var heartRateSeries = new IncidentHeartRateWindowDto(
            incident.TriggeredAt,
            windowStart,
            windowEnd,
            hrSamples);

        return Ok(IncidentDtoMapper.ToResponse(incident, incident.ElderProfile?.FullName ?? "N/A", heartRateSeries));
    }

    /// <summary>
    /// API chuyên biệt lấy chuỗi nhịp tim hoặc SpO2 T-15...T+15 phút phục vụ biểu đồ lâm sàng
    /// </summary>
    [HttpGet("{id}/heart-rate-series")]
    [Authorize]
    [ProducesResponseType(typeof(IncidentHeartRateWindowDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetIncidentHeartRateSeries(string id, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        var incident = await _db.Incidents.AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == id, ct);
        if (incident == null) return NotFound();

        var allowed = await _db.ElderCaregivers.AnyAsync(ec =>
            ec.CaregiverId == caregiverId && ec.ElderProfileId == incident.ElderProfileId && ec.IsActive, ct);
        if (!allowed) return Forbid();

        var windowStart = incident.TriggeredAt.AddMinutes(-15);
        var windowEnd = incident.TriggeredAt.AddMinutes(15);
        var seriesMetric = incident.EmergencyType == EmergencyType.LowOxygen ? "SPO2" : "HEART_RATE";
        var hrSamples = await _db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == incident.ElderProfileId
                     && m.MetricType == seriesMetric
                     && m.Timestamp >= windowStart
                     && m.Timestamp <= windowEnd)
            .OrderBy(m => m.Timestamp)
            .Select(m => new HeartRateSampleDto(m.Timestamp, m.Value, m.Unit, m.DeviceId))
            .ToListAsync(ct);

        return Ok(new IncidentHeartRateWindowDto(
            incident.TriggeredAt,
            windowStart,
            windowEnd,
            hrSamples));
    }

    /// <summary>
    /// Người thân tiếp nhận sự cố cứu hộ (Human-in-the-Loop Acknowledge)
    /// </summary>
    [HttpPost("{id}/acknowledge")]
    [HttpPost("{id}/ack")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> AcknowledgeIncident(string id, [FromBody] AcknowledgeIncidentRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
        if (incident == null)
            return NotFound(new { error = "Sự cố không tồn tại." });

        // Kiểm tra quyền BOLA
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.ElderProfileId == incident.ElderProfileId && ec.CaregiverId == caregiverId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý người cao tuổi này." });
        }

        if (incident.Status != IncidentStatus.Open)
            return await ConflictStateAsync(id, "Sự cố đã được tiếp nhận hoặc đóng. Vui lòng tải lại trạng thái.", ct);

        if (!TryReadRowVersion(request.RowVersion, out var expectedVersion))
            return BadRequest(new { error = "Thiếu hoặc sai RowVersion; hãy tải lại sự cố trước khi tiếp nhận." });
        if (incident.RowVersion == null || !incident.RowVersion.SequenceEqual(expectedVersion))
            return await ConflictStateAsync(id, "Sự cố đã thay đổi kể từ lần tải gần nhất.", ct);

        _db.Entry(incident).Property(i => i.RowVersion).OriginalValue = expectedVersion;
        var now = DateTime.UtcNow;
        var caregiverName = await _db.Caregivers
            .Where(c => c.Id == caregiverId)
            .Select(c => c.FullName)
            .FirstOrDefaultAsync(ct) ?? caregiverId;

        incident.Status = IncidentStatus.Acknowledged;
        incident.AcknowledgedAt = now;
        incident.AcknowledgedByCaregiverId = caregiverId;
        incident.ReminderCount = 0;
        incident.NextReminderAt = now.AddMinutes(_alertingOptions.StableVitalsReminderMinutes);
        incident.AcknowledgedCriticalHeartRateBpm = incident.LatestCriticalHeartRateBpm;
        incident.AcknowledgedCriticalRuleCode = incident.LatestCriticalRuleCode;
        incident.UpdatedAt = now;
        var acknowledgementNote = string.IsNullOrWhiteSpace(request.Notes)
            ? "Đang đến hỗ trợ"
            : request.Notes.Trim();

        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = id,
            ActorCaregiverId = caregiverId,
            AlertCycleNumber = incident.AlertCycleNumber,
            EventType = "ACKNOWLEDGED",
            Description = $"Người thân {caregiverName} đã tiếp nhận sự cố: {acknowledgementNote}",
            RecordedAt = now
        });
        await QueueStatusNotificationAsync(incident, caregiverId, caregiverName, "ACKNOWLEDGED", now, ct);

        try
        {
            // EF Core uses one SQL transaction for the incident, timeline and outbox writes.
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            _db.ChangeTracker.Clear();
            return await ConflictStateAsync(id, "Sự cố vừa được người khác cập nhật. Vui lòng tải lại trạng thái.", ct);
        }

        return Ok(new
        {
            status = "ACKNOWLEDGED",
            incidentId = id,
            acknowledgedAt = now,
            acknowledgedByCaregiverId = caregiverId,
            acknowledgedByName = caregiverName,
            rowVersion = Convert.ToBase64String(incident.RowVersion!)
        });
    }

    /// <summary>
    /// Đóng sự cố cứu trợ an toàn (Resolve Incident)
    /// </summary>
    [HttpPost("{id}/resolve")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ResolveIncident(string id, [FromBody] ResolveIncidentRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
        if (incident == null)
            return NotFound(new { error = "Sự cố không tồn tại." });

        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.ElderProfileId == incident.ElderProfileId && ec.CaregiverId == caregiverId && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý người cao tuổi này." });
        }

        var resolutionNotes = request.ResolutionNotes?.Trim();
        if (string.IsNullOrWhiteSpace(resolutionNotes))
            return BadRequest(new { error = "Bắt buộc nhập ghi chú lâm sàng trước khi đóng sự cố." });
        if (incident.Status != IncidentStatus.Acknowledged)
            return await ConflictStateAsync(id, "Chỉ có thể đóng sự cố đã được tiếp nhận và chưa được đóng.", ct);

        if (!TryReadRowVersion(request.RowVersion, out var expectedVersion))
            return BadRequest(new { error = "Thiếu hoặc sai RowVersion; hãy tải lại sự cố trước khi đóng." });
        if (incident.RowVersion == null || !incident.RowVersion.SequenceEqual(expectedVersion))
            return await ConflictStateAsync(id, "Sự cố đã thay đổi kể từ lần tải gần nhất.", ct);

        _db.Entry(incident).Property(i => i.RowVersion).OriginalValue = expectedVersion;

        var now = DateTime.UtcNow;
        var caregiverName = await _db.Caregivers
            .Where(c => c.Id == caregiverId)
            .Select(c => c.FullName)
            .FirstOrDefaultAsync(ct) ?? caregiverId;
        incident.Status = IncidentStatus.Resolved;
        incident.ResolvedAt = now;
        incident.ResolvedByCaregiverId = caregiverId;
        incident.ResolutionNotes = resolutionNotes;
        incident.UpdatedAt = now;

        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = id,
            ActorCaregiverId = caregiverId,
            AlertCycleNumber = incident.AlertCycleNumber,
            EventType = "RESOLVED",
            Description = $"Người thân {caregiverName} đã giải quyết sự cố: {resolutionNotes}",
            RecordedAt = now
        });

        await QueueStatusNotificationAsync(incident, caregiverId, caregiverName, "RESOLVED", now, ct);

        try
        {
            await _db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            _db.ChangeTracker.Clear();
            return await ConflictStateAsync(id, "Sự cố vừa được người khác cập nhật. Vui lòng tải lại trạng thái.", ct);
        }
        _logger.LogInformation("[INCIDENT-RESOLVED] Sự cố {IncidentId} đã đóng an toàn bởi Caregiver {CaregiverId}", id, caregiverId);

        return Ok(new
        {
            status = "RESOLVED",
            incidentId = id,
            resolvedAt = now,
            rowVersion = Convert.ToBase64String(incident.RowVersion!),
            message = "Sự cố đã được giải quyết an toàn."
        });
    }

    private static bool TryReadRowVersion(string? encoded, out byte[] rowVersion)
    {
        rowVersion = [];
        if (string.IsNullOrWhiteSpace(encoded)) return false;
        try
        {
            rowVersion = Convert.FromBase64String(encoded);
            return rowVersion.Length == 8;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private async Task<IActionResult> ConflictStateAsync(string incidentId, string error, CancellationToken ct)
    {
        var current = await _db.Incidents.AsNoTracking()
            .FirstOrDefaultAsync(i => i.Id == incidentId, ct);
        var acknowledgedByName = current?.AcknowledgedByCaregiverId == null ? null :
            await _db.Caregivers.AsNoTracking()
                .Where(c => c.Id == current.AcknowledgedByCaregiverId)
                .Select(c => c.FullName)
                .FirstOrDefaultAsync(ct);

        return Conflict(new
        {
            code = "INCIDENT_CONFLICT",
            error = current?.Status == IncidentStatus.Acknowledged && acknowledgedByName != null
                ? $"Sự cố đã được {acknowledgedByName} tiếp nhận trước. Vui lòng tải lại trạng thái."
                : error,
            status = current?.Status.ToString(),
            acknowledgedByCaregiverId = current?.AcknowledgedByCaregiverId,
            acknowledgedByName,
            acknowledgedAt = current?.AcknowledgedAt,
            rowVersion = current?.RowVersion is { Length: > 0 } version ? Convert.ToBase64String(version) : null
        });
    }

    private async Task QueueStatusNotificationAsync(Incident incident, string actorId,
        string actorName, string status, DateTime now, CancellationToken ct)
    {
        var recipients = await _db.ElderCaregivers
            .Where(ec => ec.ElderProfileId == incident.ElderProfileId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive),
                ec => ec.CaregiverId, t => t.CaregiverId,
                (ec, t) => new { ec.CaregiverId, t.PushToken })
            .Distinct()
            .ToListAsync(ct);

        foreach (var recipient in recipients)
        {
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incident.Id,
                AlertCycleNumber = incident.AlertCycleNumber,
                RecipientCaregiverId = recipient.CaregiverId,
                PushToken = recipient.PushToken,
                Title = status == "ACKNOWLEDGED" ? "Sự cố đã được tiếp nhận" : "Sự cố đã được giải quyết",
                Body = status == "ACKNOWLEDGED"
                    ? $"{actorName} đã tiếp nhận sự cố."
                    : $"{actorName} đã đóng sự cố.",
                DataPayloadJson = JsonSerializer.Serialize(new
                {
                    incidentId = incident.Id,
                    elderProfileId = incident.ElderProfileId,
                    eventType = status,
                    alertCycleNumber = incident.AlertCycleNumber,
                    actorCaregiverId = actorId,
                    siren = false
                }),
                Status = "PENDING",
                CreatedAt = now
            });
        }
    }
}
