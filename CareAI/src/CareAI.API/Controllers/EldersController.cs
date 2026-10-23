using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using CareAI.API.Middlewares;
using CareAI.Core.DTOs;
using CareAI.Core.Enums;
using CareAI.Core.Interfaces;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Services;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/elders")]
[Authorize]
public class EldersController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly IAdaptiveThresholdService _thresholdService;
    private readonly ILogger<EldersController> _logger;

    [ActivatorUtilitiesConstructor]
    public EldersController(
        CareAiDbContext db,
        IAdaptiveThresholdService thresholdService,
        ILogger<EldersController> logger)
    {
        _db = db;
        _thresholdService = thresholdService;
        _logger = logger;
    }

    public EldersController(CareAiDbContext db, ILogger<EldersController> logger)
        : this(db, null!, logger)
    {
    }

    /// <summary>
    /// Lấy ngưỡng nhịp tim an toàn hiện tại của Người cao tuổi.
    /// </summary>
    [HttpGet("{id}/thresholds")]
    [ProducesResponseType(typeof(ThresholdResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetElderThresholds(string id, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        // BOLA Check: Người thân phải được phân quyền chăm sóc Cụ này
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == id && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền xem thông tin ngưỡng của người cao tuổi này." });
        }

        var elder = await _db.ElderProfiles.AsNoTracking().FirstOrDefaultAsync(e => e.Id == id, ct);
        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        var isSleep = AdaptiveThresholdService.IsInSleepWindow(DateTime.UtcNow, elder.SleepWindowStart, elder.SleepWindowEnd);

        return Ok(new ThresholdResponse(
            ElderProfileId: elder.Id,
            RestingHeartRateMin: elder.RestingHeartRateMin,
            RestingHeartRateMax: elder.RestingHeartRateMax,
            UpdatedAt: elder.ThresholdsUpdatedAt,
            NightHeartRateMin: elder.NightHeartRateMin,
            NightHeartRateMax: elder.NightHeartRateMax,
            SleepWindowStart: elder.SleepWindowStart,
            SleepWindowEnd: elder.SleepWindowEnd,
            IsCurrentlySleepWindow: isSleep
        ));
    }

    /// <summary>
    /// Tính toán đề xuất dải ngưỡng thích nghi cá nhân hóa từ 14 ngày lịch sử đo sinh hiệu (P5/P95, kẹp trôi dạt 3 bpm/tuần).
    /// </summary>
    [HttpGet("{id}/thresholds/recommendation")]
    [ProducesResponseType(typeof(ThresholdRecommendationDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetThresholdRecommendation(string id, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        // BOLA Check
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == id && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền phân tích ngưỡng của người cao tuổi này." });
        }

        try
        {
            var recommendation = await _thresholdService.CalculateRecommendationAsync(id, ct);
            return Ok(recommendation);
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }
    }

    /// <summary>
    /// Cập nhật ngưỡng an toàn cá nhân hóa cho Người cao tuổi & làm mới tức thì IMemoryCache (Zero-Downtime Cache Invalidation).
    /// </summary>
    [HttpPut("{id}/thresholds")]
    [ProducesResponseType(typeof(ThresholdResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateThresholds(string id, [FromBody] UpdateThresholdsRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        // BOLA Check: Người thân phải có quyền chăm sóc hợp lệ
        var isAuthorized = await _db.ElderCaregivers
            .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == id && ec.IsActive, ct);

        if (!isAuthorized)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền cập nhật ngưỡng của người cao tuổi này." });
        }

        // Kiểm tra hợp lệ dữ liệu lâm sàng
        if (request.RestingHeartRateMin < 40.0)
        {
            return BadRequest(new { error = "Ngưỡng nhịp tim tối thiểu không được thấp hơn giới hạn an toàn 40 bpm." });
        }

        if (request.RestingHeartRateMax > 160.0)
        {
            return BadRequest(new { error = "Ngưỡng nhịp tim tối đa không được vượt quá giới hạn an toàn 160 bpm." });
        }

        if (request.RestingHeartRateMin >= request.RestingHeartRateMax)
        {
            return BadRequest(new { error = "Ngưỡng nhịp tim tối thiểu phải nhỏ hơn ngưỡng tối đa." });
        }

        if (request.NightHeartRateMin.HasValue && request.NightHeartRateMin.Value < 35.0)
        {
            return BadRequest(new { error = "Ngưỡng ban đêm tối thiểu không được thấp hơn giới hạn an toàn 35 bpm." });
        }

        if (request.NightHeartRateMax.HasValue && request.NightHeartRateMax.Value > 140.0)
        {
            return BadRequest(new { error = "Ngưỡng ban đêm tối đa không được vượt quá giới hạn an toàn 140 bpm." });
        }

        if (request.NightHeartRateMin.HasValue && request.NightHeartRateMax.HasValue && request.NightHeartRateMin >= request.NightHeartRateMax)
        {
            return BadRequest(new { error = "Ngưỡng ban đêm tối thiểu phải nhỏ hơn ngưỡng tối đa." });
        }

        try
        {
            var result = await _thresholdService.UpdateThresholdsAsync(
                id,
                request.RestingHeartRateMin,
                request.RestingHeartRateMax,
                request.NightHeartRateMin,
                request.NightHeartRateMax,
                request.SleepWindowStart,
                request.SleepWindowEnd,
                ct);
            return Ok(result);
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    /// <summary>
    /// Xóa an toàn hồ sơ Người cao tuổi (UC-13): Xác thực mật khẩu cấp 2, Soft-Delete & Ẩn danh hóa PII
    /// RBAC: Chỉ người bảo hộ chính (Primary Caregiver) mới có quyền xóa. Secondary Caregiver -> 403 Forbidden.
    /// </summary>
    [HttpDelete("{id}")]
    [ProducesResponseType(typeof(DeleteElderResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> DeleteElder(
        string id,
        [FromBody] DeleteElderRequest request,
        [FromServices] IMemoryCache cache,
        CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        if (string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest(new { error = "Vui lòng nhập mật khẩu tài khoản cấp 2 để xác nhận xóa hồ sơ." });
        }

        // Kiểm tra quyền RBAC của Caregiver trên Elder này
        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == id && ec.IsActive, ct);

        if (relation == null)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý hồ sơ người cao tuổi này." });
        }

        if (relation.Role != CaregiverRole.Primary)
        {
            _logger.LogWarning("[ELDER-DELETE-FORBIDDEN] Secondary Caregiver {CaregiverId} cố gắng xóa hồ sơ Elder {ElderId}", caregiverId, id);
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền xóa hồ sơ người cao tuổi." });
        }

        // Xác thực Mật khẩu Cấp 2 của Primary Caregiver
        var caregiver = await _db.Caregivers.FirstOrDefaultAsync(c => c.Id == caregiverId, ct);
        if (caregiver == null || !AuthController.VerifyPassword(request.Password, caregiver.PasswordHash))
        {
            _logger.LogWarning("[ELDER-DELETE-AUTH-FAIL] Xác thực mật khẩu cấp 2 thất bại cho Caregiver {CaregiverId} khi cố xóa Elder {ElderId}", caregiverId, id);
            return BadRequest(new { error = "Mật khẩu xác nhận cấp 2 không chính xác. Thao tác xóa hồ sơ bị từ chối vì lý do bảo mật." });
        }

        var elder = await _db.ElderProfiles.FirstOrDefaultAsync(e => e.Id == id && !e.IsDeleted, ct);
        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi hoặc hồ sơ đã bị xóa trước đó." });
        }

        // Bất biến an toàn y tế: Không thể xóa hồ sơ khi đang có sự cố cấp cứu mở hoặc đã tiếp nhận chưa giải quyết
        var hasActiveIncident = await _db.Incidents
            .AnyAsync(i => i.ElderProfileId == id && (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        if (hasActiveIncident)
        {
            _logger.LogWarning("[ELDER-DELETE-CONFLICT] Từ chối xóa Elder {ElderId} do đang có sự cố cấp cứu chưa giải quyết.", id);
            return StatusCode(StatusCodes.Status409Conflict, new { error = "Không thể xóa hồ sơ người cao tuổi khi đang có sự cố cấp cứu chưa giải quyết. Vui lòng tiếp nhận hoặc đóng sự cố trước." });
        }

        var now = DateTime.UtcNow;

        // 1. Soft-Delete & Ẩn danh hóa dữ liệu định danh PII (GDPR / Health Data Compliance)
        elder.IsDeleted = true;
        elder.FullName = "NGƯỜI DÙNG ĐÃ XÓA (ANONYMIZED)";
        elder.MedicalNotes = null;
        elder.EmergencyContact = null;
        elder.PairingPin = null;
        elder.PairingPinHash = null;
        elder.PinExpiresAt = null;
        elder.UpdatedAt = now;

        // 2. Vô hiệu hóa toàn bộ thiết bị đang gắn với Cụ và xóa Token Hash
        var devices = await _db.DeviceRegistrations.Where(d => d.ElderProfileId == id).ToListAsync(ct);
        foreach (var device in devices)
        {
            device.IsActive = false;
            device.DeviceTokenHash = string.Empty;
            device.UpdatedAt = now;
            DeviceTokenAuthMiddleware.InvalidateDevice(cache, device.Id);
            cache.Set($"blacklist:dev:{device.Id}", true, TimeSpan.FromDays(30));
        }

        // 3. Vô hiệu hóa liên kết thành viên nhóm gia đình
        var elderCaregivers = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == id).ToListAsync(ct);
        foreach (var ec in elderCaregivers)
        {
            ec.IsActive = false;
        }

        // 4. Hủy mọi mã mời gia đình đang chờ của Cụ
        var invitations = await _db.FamilyInvitations.Where(fi => fi.ElderProfileId == id && !fi.IsUsed).ToListAsync(ct);
        foreach (var inv in invitations)
        {
            inv.IsUsed = true;
        }

        await _db.SaveChangesAsync(ct);
        _logger.LogWarning("[ELDER-DELETED] Primary Caregiver {CaregiverId} đã xóa mềm và ẩn danh hóa toàn bộ hồ sơ Cụ {ElderId}", caregiverId, id);

        return Ok(new DeleteElderResponse(
            id,
            "DELETED_ANONYMIZED",
            "Hồ sơ người cao tuổi đã được xóa mềm và ẩn danh hóa dữ liệu cá nhân (PII) thành công."
        ));
    }
}
