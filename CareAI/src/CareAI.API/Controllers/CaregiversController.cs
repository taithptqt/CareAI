using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/caregivers")]
[Authorize]
public class CaregiversController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<CaregiversController> _logger;

    public CaregiversController(CareAiDbContext db, ILogger<CaregiversController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Đăng ký hoặc làm mới FCM Push Token của Người thân (Ngăn ngừa FCM Token Rot)
    /// </summary>
    [HttpPost("push-token")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> RegisterPushToken([FromBody] RegisterPushTokenRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
        {
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });
        }

        if (string.IsNullOrWhiteSpace(request.PushToken))
        {
            return BadRequest(new { error = "PushToken không được để trống." });
        }

        var existingToken = await _db.CaregiverPushTokens
            .FirstOrDefaultAsync(t => t.PushToken == request.PushToken, ct);

        if (existingToken != null)
        {
            existingToken.CaregiverId = caregiverId;
            existingToken.DeviceModel = request.DeviceModel ?? existingToken.DeviceModel;
            existingToken.IsActive = true;
            existingToken.DeactivatedAt = null;
            existingToken.DeactivationReason = null;
            existingToken.LastUsedAt = DateTime.UtcNow;
        }
        else
        {
            _db.CaregiverPushTokens.Add(new CaregiverPushToken
            {
                Id = Guid.NewGuid().ToString(),
                CaregiverId = caregiverId,
                PushToken = request.PushToken,
                DeviceModel = request.DeviceModel ?? "Unknown Device",
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                LastUsedAt = DateTime.UtcNow
            });
        }

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[PUSH-TOKEN] Cập nhật thành công Push Token cho Người thân {CaregiverId}", caregiverId);

        return Ok(new { status = "TOKEN_REGISTERED", caregiverId });
    }

    /// <summary>
    /// Danh sách Người cao tuổi mà Người thân này đang chăm sóc (UC-02 / UC-10)
    /// </summary>
    [HttpGet("elders")]
    [ProducesResponseType(typeof(List<ElderItemDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetMyElders(CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var elderCaregivers = await _db.ElderCaregivers
            .AsNoTracking()
            .Where(ec => ec.CaregiverId == caregiverId && ec.IsActive)
            .Include(ec => ec.ElderProfile)
                .ThenInclude(e => e.Devices)
            .ToListAsync(ct);

        var now = DateTime.UtcNow;
        var result = elderCaregivers
            .Where(ec => ec.ElderProfile != null)
            .Select(ec =>
            {
                var elder = ec.ElderProfile!;
                var activeDevices = elder.Devices.Where(d => d.IsActive).ToList();
                var isOnline = activeDevices.Any(d => d.LastHeartbeat >= now.AddMinutes(-15));
                var deviceStatus = isOnline ? "ONLINE" : "OFFLINE";

                return new ElderItemDto(
                    elder.Id,
                    elder.FullName,
                    elder.DateOfBirth,
                    elder.MedicalNotes,
                    elder.EmergencyContact,
                    elder.PairingPin,
                    elder.PinExpiresAt,
                    activeDevices.Count,
                    deviceStatus
                );
            })
            .ToList();

        return Ok(result);
    }

    /// <summary>
    /// Tạo Hồ sơ Người cao tuổi mới và tự động gán Người thân hiện tại làm Primary Caregiver (UC-02)
    /// </summary>
    [HttpPost("elders")]
    [ProducesResponseType(typeof(ElderItemDto), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> CreateElder([FromBody] CreateElderRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        if (string.IsNullOrWhiteSpace(request.FullName))
            return BadRequest(new { error = "Họ tên người cao tuổi không được để trống." });

        var elder = new ElderProfile
        {
            Id = Guid.NewGuid().ToString(),
            FullName = request.FullName.Trim(),
            DateOfBirth = request.DateOfBirth,
            MedicalNotes = request.MedicalNotes?.Trim(),
            EmergencyContact = request.EmergencyContact?.Trim(),
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };

        var relation = new ElderCaregiver
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = elder.Id,
            CaregiverId = caregiverId,
            Role = CaregiverRole.Primary,
            IsActive = true,
            AssignedAt = DateTime.UtcNow
        };

        _db.ElderProfiles.Add(elder);
        _db.ElderCaregivers.Add(relation);
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("[ELDER-CREATED] Người thân {CaregiverId} đã tạo hồ sơ cho Cụ {ElderId} ({FullName})", caregiverId, elder.Id, elder.FullName);

        var dto = new ElderItemDto(
            elder.Id,
            elder.FullName,
            elder.DateOfBirth,
            elder.MedicalNotes,
            elder.EmergencyContact,
            elder.PairingPin,
            elder.PinExpiresAt,
            0,
            "OFFLINE"
        );

        return StatusCode(StatusCodes.Status201Created, dto);
    }

    /// <summary>
    /// Chỉnh sửa thông tin hồ sơ Người cao tuổi (UC-02)
    /// RBAC: Chỉ Primary Caregiver mới có quyền chỉnh sửa. Secondary Caregiver -> 403 Forbidden.
    /// </summary>
    [HttpPut("elders/{id}")]
    [ProducesResponseType(typeof(ElderItemDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateElder(string id, [FromBody] UpdateElderRequest request, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized(new { error = "Không tìm thấy danh tính người dùng trong phiên làm việc." });

        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == id && ec.IsActive, ct);

        if (relation == null)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý người cao tuổi này." });
        }

        if (relation.Role != CaregiverRole.Primary)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền chỉnh sửa hồ sơ người cao tuổi." });
        }

        var elder = await _db.ElderProfiles
            .Include(e => e.Devices)
            .FirstOrDefaultAsync(e => e.Id == id && !e.IsDeleted, ct);

        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        if (!string.IsNullOrWhiteSpace(request.FullName))
        {
            elder.FullName = request.FullName.Trim();
        }

        if (request.DateOfBirth.HasValue)
        {
            elder.DateOfBirth = request.DateOfBirth.Value;
        }

        elder.MedicalNotes = request.MedicalNotes?.Trim() ?? elder.MedicalNotes;
        elder.EmergencyContact = request.EmergencyContact?.Trim() ?? elder.EmergencyContact;
        elder.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[ELDER-UPDATED] Primary Caregiver {CaregiverId} đã cập nhật hồ sơ Cụ {ElderId} ({FullName})", caregiverId, elder.Id, elder.FullName);

        var activeDevices = elder.Devices.Where(d => d.IsActive).ToList();
        var isOnline = activeDevices.Any(d => d.LastHeartbeat >= DateTime.UtcNow.AddMinutes(-15));

        return Ok(new ElderItemDto(
            elder.Id,
            elder.FullName,
            elder.DateOfBirth,
            elder.MedicalNotes,
            elder.EmergencyContact,
            elder.PairingPin,
            elder.PinExpiresAt,
            activeDevices.Count,
            isOnline ? "ONLINE" : "OFFLINE"
        ));
    }
}

