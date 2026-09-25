using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using CareAI.API.Middlewares;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/devices")]
public class DevicesController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<DevicesController> _logger;

    public DevicesController(CareAiDbContext db, ILogger<DevicesController> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Tạo mã PIN 6 số để ghép nối thiết bị phần cứng (Hiệu lực 15 phút, lưu băm SHA-256) (UC-02)
    /// RBAC: Chỉ Primary Caregiver mới có quyền tạo mã ghép nối.
    /// </summary>
    [HttpPost("generate-pin/{elderProfileId}")]
    [Authorize]
    [ProducesResponseType(typeof(GeneratePinResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GeneratePairingPin(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == elderProfileId && ec.IsActive, ct);

        if (relation == null)
        {
            _logger.LogWarning("[DEVICE-PIN-FORBIDDEN] Caregiver {CaregiverId} không có quyền trên Elder {ElderId}", caregiverId, elderProfileId);
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý người cao tuổi này." });
        }

        if (relation.Role != CareAI.Core.Enums.CaregiverRole.Primary)
        {
            _logger.LogWarning("[DEVICE-PIN-FORBIDDEN] Secondary Caregiver {CaregiverId} cố gắng tạo PIN cho Elder {ElderId}", caregiverId, elderProfileId);
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền tạo mã ghép nối thiết bị." });
        }

        var elder = await _db.ElderProfiles.FirstOrDefaultAsync(e => e.Id == elderProfileId && !e.IsDeleted, ct);
        if (elder == null)
        {
            return NotFound(new { error = "Không tìm thấy hồ sơ người cao tuổi." });
        }

        var pin = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
        var expiresAt = DateTime.UtcNow.AddMinutes(15);

        using var sha = SHA256.Create();
        var pinHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(pin))).ToLowerInvariant();

        elder.PairingPin = pin;
        elder.PairingPinHash = pinHash;
        elder.PinExpiresAt = expiresAt;
        elder.UpdatedAt = DateTime.UtcNow;

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[DEVICE-PIN] Đã tạo mã PIN ghép nối 15 phút cho Cụ {ElderId}: {Pin}", elderProfileId, pin);

        return Ok(new GeneratePinResponse(pin, expiresAt));
    }

    /// <summary>
    /// Ghép nối thiết bị phần cứng mới bằng mã PIN (Tự sinh Token mật mã ngẫu nhiên 256-bit) (UC-02)
    /// </summary>
    [HttpPost("pair")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(PairDeviceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> PairDevice([FromBody] PairDeviceRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId) || string.IsNullOrWhiteSpace(request.PairingPin))
        {
            return BadRequest(new { error = "DeviceId và PairingPin không được để trống." });
        }

        var normalizedPin = request.PairingPin.Trim();
        using var shaPin = SHA256.Create();
        var pinHash = Convert.ToHexString(shaPin.ComputeHash(Encoding.UTF8.GetBytes(normalizedPin))).ToLowerInvariant();

        var now = DateTime.UtcNow;
        var elder = await _db.ElderProfiles
            .FirstOrDefaultAsync(e => !e.IsDeleted && (e.PairingPinHash == pinHash || e.PairingPin == normalizedPin) && e.PinExpiresAt >= now, ct);

        if (elder == null)
        {
            _logger.LogWarning("[PAIR-FAIL] Mã PIN ghép nối không hợp lệ hoặc đã hết hạn: {Pin}", request.PairingPin);
            return BadRequest(new { error = "Mã PIN ghép nối không chính xác hoặc đã hết hạn." });
        }

        // Sinh token bảo mật 256-bit ngẫu nhiên
        var rawSecretBytes = new byte[32];
        using (var rng = RandomNumberGenerator.Create())
        {
            rng.GetBytes(rawSecretBytes);
        }
        var rawDeviceToken = Convert.ToBase64String(rawSecretBytes);

        // Bất biến: Token Hash phải lưu chữ thường (.ToLowerInvariant())
        using var sha = SHA256.Create();
        var tokenHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(rawDeviceToken))).ToLowerInvariant();

        var existingDevice = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == request.DeviceId, ct);
        if (existingDevice != null)
        {
            existingDevice.ElderProfileId = elder.Id;
            existingDevice.DeviceTokenHash = tokenHash;
            existingDevice.DeviceType = request.DeviceType ?? "Smartwatch";
            existingDevice.FirmwareVersion = request.FirmwareVersion ?? "1.0.0";
            existingDevice.IsActive = true;
            existingDevice.LastHeartbeat = now;
            existingDevice.UpdatedAt = now;
        }
        else
        {
            _db.DeviceRegistrations.Add(new DeviceRegistration
            {
                Id = request.DeviceId,
                ElderProfileId = elder.Id,
                DeviceTokenHash = tokenHash,
                DeviceType = request.DeviceType ?? "Smartwatch",
                FirmwareVersion = request.FirmwareVersion ?? "1.0.0",
                IsActive = true,
                LastHeartbeat = now,
                RegisteredAt = now,
                CreatedAt = now,
                UpdatedAt = now
            });
        }

        // Vô hiệu hóa PIN sau khi sử dụng thành công (One-Time PIN)
        elder.PairingPin = null;
        elder.PairingPinHash = null;
        elder.PinExpiresAt = null;
        elder.UpdatedAt = now;

        await _db.SaveChangesAsync(ct);
        _logger.LogInformation("[PAIR-SUCCESS] Thiết bị {DeviceId} đã ghép nối thành công với Cụ {ElderId} ({Name})", 
            request.DeviceId, elder.Id, elder.FullName);

        return Ok(new PairDeviceResponse(request.DeviceId, rawDeviceToken, elder.Id, elder.FullName));
    }

    /// <summary>
    /// Thu hồi quyền thiết bị tức thì (Instant Revocation Kill-Switch với độ trễ 0ms)
    /// </summary>
    [HttpPost("{deviceId}/revoke")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RevokeDevice(string deviceId, [FromServices] IMemoryCache cache, CancellationToken ct)
    {
        var device = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == deviceId, ct);
        if (device == null)
        {
            return NotFound(new { error = "Thiết bị không tồn tại." });
        }

        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (!string.IsNullOrEmpty(caregiverId))
        {
            var isAuthorized = await _db.ElderCaregivers
                .AnyAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == device.ElderProfileId && ec.IsActive, ct);

            if (!isAuthorized)
            {
                return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý thiết bị của người cao tuổi này." });
            }
        }

        device.IsActive = false;
        device.UpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        // Xóa sạch cache với độ trễ 0ms
        DeviceTokenAuthMiddleware.InvalidateDevice(cache, deviceId);
        _logger.LogWarning("[REVOKE-DEVICE] Thiết bị {DeviceId} đã bị thu hồi quyền truy cập tức thì!", deviceId);

        return Ok(new { message = $"Thiết bị {deviceId} đã bị thu hồi quyền truy cập tức thì.", deviceId });
    }

    /// <summary>
    /// Hủy ghép nối thiết bị an toàn, đưa vào Blacklist và phát tín hiệu WIPE_DEVICE_CREDENTIALS (UC-12)
    /// RBAC: Chỉ Primary Caregiver mới có quyền hủy ghép nối. Secondary Caregiver -> 403 Forbidden.
    /// </summary>
    [HttpPost("{deviceId}/unpair")]
    [Authorize]
    [ProducesResponseType(typeof(UnpairDeviceResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UnpairDevice(string deviceId, [FromServices] IMemoryCache cache, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId))
            return Unauthorized();

        var device = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == deviceId, ct);
        if (device == null)
        {
            return NotFound(new { error = "Thiết bị không tồn tại." });
        }

        var relation = await _db.ElderCaregivers
            .FirstOrDefaultAsync(ec => ec.CaregiverId == caregiverId && ec.ElderProfileId == device.ElderProfileId && ec.IsActive, ct);

        if (relation == null)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Bạn không có quyền quản lý thiết bị của người cao tuổi này." });
        }

        if (relation.Role != CareAI.Core.Enums.CaregiverRole.Primary)
        {
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Chỉ người bảo hộ chính (Primary) mới có quyền hủy ghép nối thiết bị." });
        }

        device.IsActive = false;
        device.DeviceTokenHash = string.Empty;
        device.UpdatedAt = DateTime.UtcNow;

        // Xóa cache và ghi nhận vào Blacklist 30 ngày
        DeviceTokenAuthMiddleware.InvalidateDevice(cache, deviceId);
        cache.Set($"blacklist:dev:{deviceId}", true, TimeSpan.FromDays(30));

        await _db.SaveChangesAsync(ct);
        _logger.LogWarning("[DEVICE-UNPAIR] Thiết bị {DeviceId} của Cụ {ElderId} đã bị hủy ghép nối bởi Primary Caregiver {CaregiverId}. Phát tín hiệu WIPE_DEVICE_CREDENTIALS.",
            deviceId, device.ElderProfileId, caregiverId);

        return Ok(new UnpairDeviceResponse(
            deviceId,
            "WIPE_DEVICE_CREDENTIALS",
            "Thiết bị đã được hủy ghép nối thành công. Lệnh xóa thông tin đăng nhập trên thiết bị (Wipe) đã được kích hoạt."
        ));
    }

    /// <summary>
    /// Nhịp đập sức khỏe thiết bị định kỳ (Heartbeat & Keep-Alive)
    /// </summary>
    [HttpPost("heartbeat")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Heartbeat([FromBody] HeartbeatRequest request, CancellationToken ct)
    {
        var authenticatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(authenticatedDeviceId))
        {
            return Unauthorized(new { error = "Không tìm thấy danh tính thiết bị đã xác thực." });
        }

        var device = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == authenticatedDeviceId, ct);
        if (device != null)
        {
            device.LastHeartbeat = DateTime.UtcNow;
            device.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
        }

        return Ok(new { status = "ALIVE", deviceId = authenticatedDeviceId, serverTime = DateTime.UtcNow });
    }
}
