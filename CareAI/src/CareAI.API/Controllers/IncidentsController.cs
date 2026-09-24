using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/incidents")]
public class IncidentsController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly ILogger<IncidentsController> _logger;

    public IncidentsController(
        CareAiDbContext db,
        TelemetryEngine telemetryEngine,
        ILogger<IncidentsController> logger)
    {
        _db = db;
        _telemetryEngine = telemetryEngine;
        _logger = logger;
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

        var result = incidents.Select(i => new IncidentResponseDto(
            i.Id,
            i.ElderProfileId,
            i.ElderProfile?.FullName ?? "N/A",
            i.TriggeredByDeviceId,
            i.EmergencyType,
            i.Severity.ToString(),
            i.Status.ToString(),
            i.TriggeredAt,
            i.AcknowledgedAt,
            i.AcknowledgedByCaregiverId,
            i.ResolvedAt,
            i.ResolvedByCaregiverId,
            i.ResolutionNotes,
            i.TimelineEvents.OrderBy(t => t.RecordedAt).Select(t => new IncidentTimelineDto(t.EventType, t.Description, t.RecordedAt)).ToList()
        )).ToList();

        return Ok(result);
    }

    /// <summary>
    /// Người thân tiếp nhận sự cố cứu hộ (Human-in-the-Loop Acknowledge)
    /// </summary>
    [HttpPost("{id}/ack")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
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

        if (incident.Status == IncidentStatus.Open)
        {
            var now = DateTime.UtcNow;
            incident.Status = IncidentStatus.Acknowledged;
            incident.AcknowledgedAt = now;
            incident.AcknowledgedByCaregiverId = caregiverId;
            incident.UpdatedAt = now;

            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = id,
                EventType = "ACKNOWLEDGED",
                Description = $"Người thân ({caregiverId}) đã tiếp nhận sự cố: {request.Notes ?? "Đang đến hỗ trợ"}",
                RecordedAt = now
            });

            try
            {
                await _db.SaveChangesAsync(ct);
            }
            catch (DbUpdateConcurrencyException)
            {
                return StatusCode(StatusCodes.Status409Conflict, new { error = "Sự cố vừa được cập nhật bởi tiến trình khác. Vui lòng tải lại trang." });
            }
        }

        return Ok(new { status = "ACKNOWLEDGED", incidentId = id });
    }

    /// <summary>
    /// Đóng sự cố cứu trợ an toàn (Resolve Incident)
    /// </summary>
    [HttpPost("{id}/resolve")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
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

        var now = DateTime.UtcNow;
        incident.Status = IncidentStatus.Resolved;
        incident.ResolvedAt = now;
        incident.ResolvedByCaregiverId = caregiverId;
        incident.ResolutionNotes = request.ResolutionNotes;
        incident.UpdatedAt = now;

        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = id,
            EventType = "RESOLVED",
            Description = $"Sự cố đã được giải quyết an toàn: {request.ResolutionNotes}",
            RecordedAt = now
        });

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[INCIDENT-RESOLVED] Sự cố {IncidentId} đã đóng an toàn bởi Caregiver {CaregiverId}", id, caregiverId);

        return Ok(new { status = "RESOLVED", incidentId = id, message = "Sự cố đã được giải quyết an toàn." });
    }
}
