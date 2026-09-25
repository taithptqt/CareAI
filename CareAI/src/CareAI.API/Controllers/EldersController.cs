using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
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

    public EldersController(
        CareAiDbContext db,
        IAdaptiveThresholdService thresholdService,
        ILogger<EldersController> logger)
    {
        _db = db;
        _thresholdService = thresholdService;
        _logger = logger;
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
}
