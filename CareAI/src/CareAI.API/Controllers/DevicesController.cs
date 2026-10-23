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
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/devices")]
public class DevicesController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<DevicesController> _logger;
    private readonly DeviceStaleEngine _staleEngine;

    [ActivatorUtilitiesConstructor]
    public DevicesController(
        CareAiDbContext db,
        ILogger<DevicesController> logger,
        DeviceStaleEngine? staleEngine = null)
    {
        _db = db;
        _logger = logger;
        _staleEngine = staleEngine ?? new DeviceStaleEngine(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<DeviceStaleEngine>.Instance);
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
    public async Task<IActionResult> PairDevice(
        [FromBody] PairDeviceRequest request,
        CancellationToken ct = default,
        [FromServices] IMemoryCache? cache = null)
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

        var targetDeviceType = request.DeviceType ?? "Smartwatch";
        var isWatch = targetDeviceType.Contains("watch", StringComparison.OrdinalIgnoreCase) ||
                      string.Equals(targetDeviceType, "WearOS", StringComparison.OrdinalIgnoreCase);
        var isPhone = string.Equals(targetDeviceType, "Smartphone", StringComparison.OrdinalIgnoreCase) ||
                      string.Equals(targetDeviceType, "SMARTPHONE_COMPANION", StringComparison.OrdinalIgnoreCase);

        var existingDevice = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == request.DeviceId, ct);
        if (existingDevice != null)
        {
            existingDevice.ElderProfileId = elder.Id;
            existingDevice.DeviceTokenHash = tokenHash;
            existingDevice.DeviceType = targetDeviceType;
            existingDevice.DeviceModel = request.DeviceModel ?? existingDevice.DeviceModel;
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
                DeviceType = targetDeviceType,
                DeviceModel = request.DeviceModel,
                FirmwareVersion = request.FirmwareVersion ?? "1.0.0",
                IsActive = true,
                LastHeartbeat = now,
                RegisteredAt = now,
                CreatedAt = now,
                UpdatedAt = now
            });
        }

        // Tự động vô hiệu hóa các thiết bị cũ cùng loại của Cụ để tránh thiết bị "ma" (ghost devices)
        if (isWatch)
        {
            var oldWatches = await _db.DeviceRegistrations
                .Where(d => d.ElderProfileId == elder.Id &&
                            d.Id != request.DeviceId &&
                            d.IsActive &&
                            (d.DeviceType == "Smartwatch" || d.DeviceType == "AppleWatch" || d.DeviceType == "GalaxyWatch" || d.DeviceType == "WearOS"))
                .ToListAsync(ct);
            foreach (var w in oldWatches)
            {
                w.IsActive = false;
                w.UpdatedAt = now;
                if (cache != null) DeviceTokenAuthMiddleware.InvalidateDevice(cache, w.Id);
            }
        }
        else if (isPhone)
        {
            var oldPhones = await _db.DeviceRegistrations
                .Where(d => d.ElderProfileId == elder.Id &&
                            d.Id != request.DeviceId &&
                            d.IsActive &&
                            (d.DeviceType == "Smartphone" || d.DeviceType == "SMARTPHONE_COMPANION"))
                .ToListAsync(ct);
            foreach (var p in oldPhones)
            {
                p.IsActive = false;
                p.UpdatedAt = now;
                if (cache != null) DeviceTokenAuthMiddleware.InvalidateDevice(cache, p.Id);
            }
        }

        // Xóa cache của chính thiết bị này (nếu đã từng lưu cache token cũ trước khi re-pair)
        if (cache != null) DeviceTokenAuthMiddleware.InvalidateDevice(cache, request.DeviceId);

        // Vô hiệu hóa PIN sau khi sử dụng thành công (One-Time PIN)
        elder.PairingPin = null;
        elder.PairingPinHash = null;
        elder.PinExpiresAt = null;
        elder.UpdatedAt = now;

        await _db.SaveChangesAsync(ct);
        await _staleEngine.TryAutoResolveStaleIncidentAsync(elder.Id, now, ct);
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
        cache.Set($"blacklist:dev:{deviceId}", true, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromDays(30),
            Size = 1
        });

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
        object? activeIncidentInfo = null;
        string? elderFullName = null;

        if (device != null)
        {
            device.LastHeartbeat = DateTime.UtcNow;
            device.UpdatedAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);

            elderFullName = await _db.ElderProfiles.AsNoTracking()
                .Where(e => e.Id == device.ElderProfileId && !e.IsDeleted)
                .Select(e => e.FullName)
                .FirstOrDefaultAsync(ct);

            // Truy vấn sự cố đang mở hoặc đã tiếp nhận của người cao tuổi này
            var active = await _db.Incidents
                .AsNoTracking()
                .Where(i => i.ElderProfileId == device.ElderProfileId &&
                           (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged))
                .OrderByDescending(i => i.TriggeredAt)
                .Select(i => new { i.Id, Status = i.Status.ToString().ToUpperInvariant(), i.AcknowledgedByCaregiverId, i.AcknowledgedAt })
                .FirstOrDefaultAsync(ct);

            if (active != null)
            {
                string? ackName = null;
                if (!string.IsNullOrEmpty(active.AcknowledgedByCaregiverId))
                {
                    ackName = await _db.Caregivers.AsNoTracking()
                        .Where(c => c.Id == active.AcknowledgedByCaregiverId)
                        .Select(c => c.FullName).FirstOrDefaultAsync(ct) ?? active.AcknowledgedByCaregiverId;
                }
                activeIncidentInfo = new
                {
                    incidentId = active.Id,
                    status = active.Status,
                    acknowledgedByName = ackName,
                    acknowledgedAt = active.AcknowledgedAt
                };
            }
        }

        return Ok(new
        {
            status = "ALIVE",
            deviceId = authenticatedDeviceId,
            elderName = elderFullName,
            serverTime = DateTime.UtcNow,
            activeIncident = activeIncidentInfo
        });
    }

    /// <summary>
    /// Kiểm tra trạng thái phản hồi sự cố khẩn cấp dành cho thiết bị người cao tuổi (Closed-Loop Telecare Feedback)
    /// </summary>
    [HttpGet("active-incident")]
    [ProducesResponseType(typeof(DeviceActiveIncidentResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> GetActiveIncidentForDevice(CancellationToken ct)
    {
        var authenticatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(authenticatedDeviceId))
        {
            return Unauthorized(new { error = "Không tìm thấy danh tính thiết bị đã xác thực." });
        }

        var device = await _db.DeviceRegistrations.AsNoTracking().FirstOrDefaultAsync(d => d.Id == authenticatedDeviceId && d.IsActive, ct);
        if (device == null)
        {
            return Unauthorized(new { error = "Thiết bị không tồn tại hoặc đã bị vô hiệu hóa." });
        }

        // 1. Kiểm tra sự cố Active (Open hoặc Acknowledged)
        var activeIncident = await _db.Incidents
            .AsNoTracking()
            .Include(i => i.TimelineEvents)
            .Where(i => i.ElderProfileId == device.ElderProfileId &&
                       (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged))
            .OrderByDescending(i => i.TriggeredAt)
            .FirstOrDefaultAsync(ct);

        if (activeIncident != null)
        {
            string? acknowledgedByName = null;
            if (!string.IsNullOrEmpty(activeIncident.AcknowledgedByCaregiverId))
            {
                acknowledgedByName = await _db.Caregivers
                    .AsNoTracking()
                    .Where(c => c.Id == activeIncident.AcknowledgedByCaregiverId)
                    .Select(c => c.FullName)
                    .FirstOrDefaultAsync(ct) ?? activeIncident.AcknowledgedByCaregiverId;
            }

            var ackEvent = activeIncident.TimelineEvents
                .Where(e => e.EventType == "ACKNOWLEDGED")
                .OrderByDescending(e => e.RecordedAt)
                .FirstOrDefault();

            return Ok(new DeviceActiveIncidentResponse(
                HasActiveIncident: true,
                IncidentId: activeIncident.Id,
                Status: activeIncident.Status.ToString().ToUpperInvariant(),
                EmergencyType: activeIncident.EmergencyType,
                TriggeredAt: activeIncident.TriggeredAt,
                AcknowledgedAt: activeIncident.AcknowledgedAt,
                AcknowledgedByName: acknowledgedByName,
                AcknowledgedNote: ackEvent?.Description,
                ResolvedAt: null,
                ResolvedByName: null,
                ResolutionNotes: null
            ));
        }

        // 2. Nếu không có sự cố Active, kiểm tra sự cố được giải quyết gần nhất trong vòng 15 phút
        var recentlyResolved = await _db.Incidents
            .AsNoTracking()
            .Where(i => i.ElderProfileId == device.ElderProfileId &&
                        i.Status == IncidentStatus.Resolved &&
                        i.ResolvedAt >= DateTime.UtcNow.AddMinutes(-15))
            .OrderByDescending(i => i.ResolvedAt)
            .FirstOrDefaultAsync(ct);

        if (recentlyResolved != null)
        {
            string? resolvedByName = null;
            if (!string.IsNullOrEmpty(recentlyResolved.ResolvedByCaregiverId))
            {
                resolvedByName = await _db.Caregivers
                    .AsNoTracking()
                    .Where(c => c.Id == recentlyResolved.ResolvedByCaregiverId)
                    .Select(c => c.FullName)
                    .FirstOrDefaultAsync(ct) ?? recentlyResolved.ResolvedByCaregiverId;
            }

            return Ok(new DeviceActiveIncidentResponse(
                HasActiveIncident: false,
                IncidentId: recentlyResolved.Id,
                Status: "RESOLVED",
                EmergencyType: recentlyResolved.EmergencyType,
                TriggeredAt: recentlyResolved.TriggeredAt,
                AcknowledgedAt: recentlyResolved.AcknowledgedAt,
                AcknowledgedByName: null,
                AcknowledgedNote: null,
                ResolvedAt: recentlyResolved.ResolvedAt,
                ResolvedByName: resolvedByName,
                ResolutionNotes: recentlyResolved.ResolutionNotes
            ));
        }

        // 3. Hoàn toàn bình thường
        return Ok(new DeviceActiveIncidentResponse(
            HasActiveIncident: false,
            IncidentId: null,
            Status: "NONE",
            EmergencyType: null,
            TriggeredAt: null,
            AcknowledgedAt: null,
            AcknowledgedByName: null,
            AcknowledgedNote: null,
            ResolvedAt: null,
            ResolvedByName: null,
            ResolutionNotes: null
        ));
    }

    /// <summary>
    /// Đồng bộ tên định danh đồng hồ kết nối qua Bluetooth từ trạm trung chuyển (Companion Phone)
    /// </summary>
    [HttpPost("sync-watch")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SyncWatch([FromBody] SyncWatchRequest request, CancellationToken ct)
    {
        var authenticatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(authenticatedDeviceId))
        {
            return Unauthorized(new { error = "Không tìm thấy danh tính thiết bị đã xác thực." });
        }

        var companionDevice = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == authenticatedDeviceId, ct);
        if (companionDevice == null)
        {
            return NotFound(new { error = "Không tìm thấy thiết bị trạm trung chuyển." });
        }

        var watchDevice = await _db.DeviceRegistrations
            .Where(d => d.ElderProfileId == companionDevice.ElderProfileId &&
                        d.IsActive &&
                        (d.DeviceType == "Smartwatch" || d.DeviceType == "AppleWatch" || d.DeviceType == "GalaxyWatch" || d.DeviceType == "WearOS"))
            .OrderByDescending(d => d.LastHeartbeat)
            .FirstOrDefaultAsync(ct);

        var now = DateTime.UtcNow;
        var isConnected = request.IsConnected ?? true;

        if (watchDevice != null)
        {
            // Tự động vô hiệu hóa các thiết bị đồng hồ cũ khác của Cụ nếu có
            var staleWatches = await _db.DeviceRegistrations
                .Where(d => d.ElderProfileId == companionDevice.ElderProfileId &&
                            d.Id != watchDevice.Id &&
                            d.IsActive &&
                            (d.DeviceType == "Smartwatch" || d.DeviceType == "AppleWatch" || d.DeviceType == "GalaxyWatch" || d.DeviceType == "WearOS"))
                .ToListAsync(ct);
            foreach (var stale in staleWatches)
            {
                stale.IsActive = false;
                stale.UpdatedAt = now;
            }

            if (!string.IsNullOrWhiteSpace(request.WatchModel))
            {
                watchDevice.DeviceModel = request.WatchModel;
            }

            watchDevice.DisconnectReason = isConnected ? null : request.DisconnectReason;
            if (request.IsWorn.HasValue) watchDevice.IsWatchWorn = request.IsWorn.Value;
            if (request.IsCharging.HasValue) watchDevice.IsWatchCharging = request.IsCharging.Value;
            if (request.BatteryLevel.HasValue) watchDevice.WatchBatteryLevel = request.BatteryLevel.Value;

            // Nếu đồng hồ bị ngắt kết nối với Companion Phone -> lùi LastHeartbeat để đánh dấu DISCONNECTED ngay tức thì
            watchDevice.LastHeartbeat = isConnected
                ? now
                : now.Subtract(DeviceStaleEngine.StaleAfterFor(watchDevice.DeviceType).Add(TimeSpan.FromMinutes(2)));
            watchDevice.UpdatedAt = now;
        }
        else if (!string.IsNullOrWhiteSpace(request.WatchModel))
        {
            // Tự động vô hiệu hóa các thiết bị đồng hồ cũ nếu có
            var staleWatches = await _db.DeviceRegistrations
                .Where(d => d.ElderProfileId == companionDevice.ElderProfileId &&
                            d.IsActive &&
                            (d.DeviceType == "Smartwatch" || d.DeviceType == "AppleWatch" || d.DeviceType == "GalaxyWatch" || d.DeviceType == "WearOS"))
                .ToListAsync(ct);
            foreach (var stale in staleWatches)
            {
                stale.IsActive = false;
                stale.UpdatedAt = now;
            }

            watchDevice = new DeviceRegistration
            {
                Id = $"WATCH_{companionDevice.Id.Replace("DEV_", "")}",
                ElderProfileId = companionDevice.ElderProfileId,
                DeviceTokenHash = companionDevice.DeviceTokenHash,
                DeviceType = (request.WatchModel != null && request.WatchModel.Contains("Apple Watch", StringComparison.OrdinalIgnoreCase)) ? "AppleWatch" : "Smartwatch",
                DeviceModel = request.WatchModel,
                DisconnectReason = isConnected ? null : request.DisconnectReason,
                IsWatchWorn = request.IsWorn,
                IsWatchCharging = request.IsCharging,
                WatchBatteryLevel = request.BatteryLevel,
                FirmwareVersion = "1.0.0",
                IsActive = true,
                LastHeartbeat = isConnected ? now : now.Subtract(TimeSpan.FromHours(1)),
                RegisteredAt = now,
                CreatedAt = now,
                UpdatedAt = now
            };
            _db.DeviceRegistrations.Add(watchDevice);
        }

        // Trạm trung chuyển (Companion Phone) đang thực hiện đồng bộ -> cập nhật LastHeartbeat của điện thoại luôn tươi mới
        companionDevice.LastHeartbeat = now;
        companionDevice.UpdatedAt = now;

        // Tích hợp đồng bộ bước chân thực tế từ cảm biến đồng hồ (chỉ lưu khi có giá trị thực > 0, không lưu rác)
        if (request.TodaySteps.HasValue && request.TodaySteps.Value > 0)
        {
            var startOfDayUtc = now.Date;
            var hasIntervalSteps = await _db.HealthMeasurements
                .AnyAsync(m => m.ElderProfileId == companionDevice.ElderProfileId &&
                               m.MetricType == "STEPS" &&
                               m.Timestamp >= startOfDayUtc &&
                               !m.PacketId.StartsWith("SYNC_STEPS_"), ct);

            if (!hasIntervalSteps)
            {
                var existingStepsToday = await _db.HealthMeasurements
                    .FirstOrDefaultAsync(m => m.ElderProfileId == companionDevice.ElderProfileId &&
                                              m.MetricType == "STEPS" &&
                                              m.Timestamp >= startOfDayUtc &&
                                              m.PacketId.StartsWith("SYNC_STEPS_"), ct);
                if (existingStepsToday != null)
                {
                    existingStepsToday.Value = request.TodaySteps.Value;
                    existingStepsToday.Timestamp = now;
                }
                else
                {
                    _db.HealthMeasurements.Add(new HealthMeasurement
                    {
                        ElderProfileId = companionDevice.ElderProfileId,
                        DeviceId = watchDevice?.Id ?? companionDevice.Id,
                        PacketId = $"SYNC_STEPS_{now.Ticks}",
                        MetricType = "STEPS",
                        Value = request.TodaySteps.Value,
                        Unit = "count",
                        Timestamp = now,
                        RecordedAt = now
                    });
                }
            }
            else
            {
                var legacySyncSteps = await _db.HealthMeasurements
                    .Where(m => m.ElderProfileId == companionDevice.ElderProfileId &&
                                m.MetricType == "STEPS" &&
                                m.Timestamp >= startOfDayUtc &&
                                m.PacketId.StartsWith("SYNC_STEPS_"))
                    .ToListAsync(ct);
                if (legacySyncSteps.Count > 0)
                {
                    _db.HealthMeasurements.RemoveRange(legacySyncSteps);
                }
            }
        }

        // Đồng bộ các chỉ số sinh hiệu thời gian thực từ cảm biến đồng hồ (chỉ lưu giá trị thực, không lưu rác)
        if (request.HeartRate.HasValue && request.HeartRate.Value > 0 && double.IsFinite(request.HeartRate.Value))
        {
            _db.HealthMeasurements.Add(new HealthMeasurement
            {
                ElderProfileId = companionDevice.ElderProfileId,
                DeviceId = watchDevice?.Id ?? companionDevice.Id,
                PacketId = $"SYNC_HR_{now.Ticks}",
                MetricType = "HEART_RATE",
                Value = request.HeartRate.Value,
                Unit = "bpm",
                Timestamp = now,
                RecordedAt = now
            });
        }

        if (request.Spo2.HasValue && request.Spo2.Value > 0 && double.IsFinite(request.Spo2.Value))
        {
            _db.HealthMeasurements.Add(new HealthMeasurement
            {
                ElderProfileId = companionDevice.ElderProfileId,
                DeviceId = watchDevice?.Id ?? companionDevice.Id,
                PacketId = $"SYNC_SPO2_{now.Ticks}",
                MetricType = "SPO2",
                Value = request.Spo2.Value,
                Unit = "%",
                Timestamp = now,
                RecordedAt = now
            });
        }

        if (request.BpSystolic.HasValue && request.BpSystolic.Value > 0 && double.IsFinite(request.BpSystolic.Value))
        {
            _db.HealthMeasurements.Add(new HealthMeasurement
            {
                ElderProfileId = companionDevice.ElderProfileId,
                DeviceId = watchDevice?.Id ?? companionDevice.Id,
                PacketId = $"SYNC_BP_SYS_{now.Ticks}",
                MetricType = "BLOOD_PRESSURE",
                Value = request.BpSystolic.Value,
                Unit = "mmHg",
                Timestamp = now,
                RecordedAt = now
            });
            if (request.BpDiastolic.HasValue && request.BpDiastolic.Value > 0 && double.IsFinite(request.BpDiastolic.Value))
            {
                _db.HealthMeasurements.Add(new HealthMeasurement
                {
                    ElderProfileId = companionDevice.ElderProfileId,
                    DeviceId = watchDevice?.Id ?? companionDevice.Id,
                    PacketId = $"SYNC_BP_DIA_{now.Ticks}",
                    MetricType = "BP_DIASTOLIC",
                    Value = request.BpDiastolic.Value,
                    Unit = "mmHg",
                    Timestamp = now,
                    RecordedAt = now
                });
            }
        }

        async Task UpsertLastNightMetric(string metricType, double value, string unit)
        {
            var vnNow = DateTime.UtcNow.AddHours(7);
            var lastNightUtc = vnNow.Date.AddDays(-1).AddHours(22).AddHours(-7);
            var existing = await _db.HealthMeasurements
                .FirstOrDefaultAsync(m => m.ElderProfileId == companionDevice.ElderProfileId &&
                                          m.MetricType == metricType &&
                                          m.Timestamp >= lastNightUtc.AddHours(-4), ct);
            if (existing != null)
            {
                existing.Value = value;
                existing.Timestamp = lastNightUtc;
                existing.RecordedAt = now;
            }
            else
            {
                _db.HealthMeasurements.Add(new HealthMeasurement
                {
                    ElderProfileId = companionDevice.ElderProfileId,
                    DeviceId = watchDevice?.Id ?? companionDevice.Id,
                    PacketId = $"SYNC_{metricType}_{now.Ticks}",
                    MetricType = metricType,
                    Value = value,
                    Unit = unit,
                    Timestamp = lastNightUtc,
                    RecordedAt = now
                });
            }
        }

        if (request.SleepMinutes.HasValue && request.SleepMinutes.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP", request.SleepMinutes.Value, "minutes");
        }
        if (request.DeepSleepMinutes.HasValue && request.DeepSleepMinutes.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_DEEP", request.DeepSleepMinutes.Value, "minutes");
        }
        if (request.CoreSleepMinutes.HasValue && request.CoreSleepMinutes.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_CORE", request.CoreSleepMinutes.Value, "minutes");
        }
        if (request.RemSleepMinutes.HasValue && request.RemSleepMinutes.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_REM", request.RemSleepMinutes.Value, "minutes");
        }
        if (request.AwakeMinutes.HasValue && request.AwakeMinutes.Value >= 0)
        {
            await UpsertLastNightMetric("SLEEP_AWAKE", request.AwakeMinutes.Value, "minutes");
        }
        if (request.WakeCount.HasValue && request.WakeCount.Value >= 0)
        {
            await UpsertLastNightMetric("SLEEP_WAKE_COUNT", request.WakeCount.Value, "count");
        }
        if (request.MinSleepingHeartRate.HasValue && request.MinSleepingHeartRate.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_HR_MIN", request.MinSleepingHeartRate.Value, "bpm");
        }
        if (request.AvgSleepingHeartRate.HasValue && request.AvgSleepingHeartRate.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_HR_AVG", request.AvgSleepingHeartRate.Value, "bpm");
        }
        if (request.MinNightSpo2.HasValue && request.MinNightSpo2.Value > 0)
        {
            await UpsertLastNightMetric("SLEEP_SPO2_MIN", request.MinNightSpo2.Value, "%");
        }
        if (request.NightSpo2DipsCount.HasValue && request.NightSpo2DipsCount.Value >= 0)
        {
            await UpsertLastNightMetric("SLEEP_SPO2_DIPS", request.NightSpo2DipsCount.Value, "count");
        }
        if (!string.IsNullOrEmpty(request.BreathingDisturbances))
        {
            double val = request.BreathingDisturbances.Equals("ELEVATED", StringComparison.OrdinalIgnoreCase) ? 1.0 : 0.0;
            await UpsertLastNightMetric("SLEEP_APNEA_RISK", val, "status");
        }

        await _db.SaveChangesAsync(ct);
        if (isConnected)
        {
            // Hướng 3: Tự động đóng sự cố STALE_OFFLINE khi đồng hồ kết nối lại với điện thoại
            await _staleEngine.TryAutoResolveStaleIncidentAsync(companionDevice.ElderProfileId, now, ct);
        }
        _logger.LogInformation("[DEVICE-SYNC-WATCH] Companion {DeviceId} đã đồng bộ đồng hồ: {WatchModel} (IsConnected={IsConnected}, Reason={Reason}, Worn={IsWorn}, Charging={IsCharging}, Battery={BatteryLevel}, TodaySteps={TodaySteps}, HR={HR}, SpO2={SpO2}, BP={BP}, Sleep={Sleep}, Deep={Deep}, Wake={Wake}) cho Cụ {ElderId}",
            authenticatedDeviceId, request.WatchModel, isConnected, request.DisconnectReason, request.IsWorn, request.IsCharging, request.BatteryLevel, request.TodaySteps, request.HeartRate, request.Spo2, request.BpSystolic, request.SleepMinutes, request.DeepSleepMinutes, request.WakeCount, companionDevice.ElderProfileId);

        var responseDict = new Dictionary<string, object?>
        {
            ["status"] = "SYNCED",
            ["watchModel"] = request.WatchModel,
            ["isConnected"] = isConnected,
            ["disconnectReason"] = request.DisconnectReason,
            ["isWorn"] = watchDevice?.IsWatchWorn ?? request.IsWorn,
            ["isCharging"] = watchDevice?.IsWatchCharging ?? request.IsCharging,
            ["batteryLevel"] = watchDevice?.WatchBatteryLevel ?? request.BatteryLevel,
            ["todaySteps"] = request.TodaySteps,
            ["heartRate"] = request.HeartRate,
            ["spo2"] = request.Spo2,
            ["bpSystolic"] = request.BpSystolic,
            ["bpDiastolic"] = request.BpDiastolic,
            ["sleepMinutes"] = request.SleepMinutes,
            ["supportedMetrics"] = request.SupportedMetrics
        };
        if (request.DeepSleepMinutes.HasValue) responseDict["deepSleepMinutes"] = request.DeepSleepMinutes;
        if (request.CoreSleepMinutes.HasValue) responseDict["coreSleepMinutes"] = request.CoreSleepMinutes;
        if (request.RemSleepMinutes.HasValue) responseDict["remSleepMinutes"] = request.RemSleepMinutes;
        if (request.AwakeMinutes.HasValue) responseDict["awakeMinutes"] = request.AwakeMinutes;
        if (request.WakeCount.HasValue) responseDict["wakeCount"] = request.WakeCount;
        if (request.MinSleepingHeartRate.HasValue) responseDict["minSleepingHeartRate"] = request.MinSleepingHeartRate;
        if (request.AvgSleepingHeartRate.HasValue) responseDict["avgSleepingHeartRate"] = request.AvgSleepingHeartRate;
        if (request.MinNightSpo2.HasValue) responseDict["minNightSpo2"] = request.MinNightSpo2;
        if (request.NightSpo2DipsCount.HasValue) responseDict["nightSpo2DipsCount"] = request.NightSpo2DipsCount;
        if (!string.IsNullOrEmpty(request.BreathingDisturbances)) responseDict["breathingDisturbances"] = request.BreathingDisturbances;

        return Ok(responseDict);
    }
}
