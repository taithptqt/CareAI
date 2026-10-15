using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Middlewares;

public record CachedDeviceAuthInfo(string DeviceTokenHash, bool IsActive);

public class DeviceTokenAuthMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<DeviceTokenAuthMiddleware> _logger;

    public DeviceTokenAuthMiddleware(RequestDelegate next, ILogger<DeviceTokenAuthMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    /// <summary>
    /// Thu hồi tức thì quyền thiết bị khỏi Cache (Instant Revocation Kill-Switch với độ trễ 0ms).
    /// </summary>
    public static void InvalidateDevice(IMemoryCache cache, string deviceId)
    {
        cache.Remove($"auth:dev:{deviceId}");
    }

    public async Task InvokeAsync(HttpContext context, CareAiDbContext db, IMemoryCache cache)
    {
        var path = context.Request.Path.Value ?? string.Empty;

        // Bỏ qua các endpoint không yêu cầu xác thực thiết bị
        if (path.StartsWith("/healthz", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/health", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/auth", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/caregivers", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/elders", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/invitations", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/dashboard", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/swagger", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        // Bỏ qua nếu là endpoint của Incidents dành cho Caregiver (active, ack, resolve, call)
        var deviceEvidenceUpload = path.StartsWith("/api/v1/incidents/", StringComparison.OrdinalIgnoreCase) &&
            (path.EndsWith("/photo", StringComparison.OrdinalIgnoreCase) ||
             path.EndsWith("/location", StringComparison.OrdinalIgnoreCase)) &&
            HttpMethods.IsPost(context.Request.Method);
        if (path.StartsWith("/api/v1/incidents", StringComparison.OrdinalIgnoreCase) &&
            !path.Equals("/api/v1/incidents/sos", StringComparison.OrdinalIgnoreCase) && !deviceEvidenceUpload)
        {
            await _next(context);
            return;
        }

        // Bỏ qua nếu là endpoint của Devices dành cho Caregiver (pair, revoke, unpair, generate-pin)
        if (path.StartsWith("/api/v1/devices/pair", StringComparison.OrdinalIgnoreCase) ||
            path.Contains("/revoke", StringComparison.OrdinalIgnoreCase) ||
            path.Contains("/unpair", StringComparison.OrdinalIgnoreCase) ||
            path.Contains("/generate-pin", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        // Các endpoint thiết bị phần cứng bắt buộc xác thực:
        if (path.StartsWith("/api/v1/telemetry", StringComparison.OrdinalIgnoreCase) ||
            path.Equals("/api/v1/incidents/sos", StringComparison.OrdinalIgnoreCase) ||
            deviceEvidenceUpload ||
            path.StartsWith("/api/v1/devices/heartbeat", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/api/v1/devices/sync-watch", StringComparison.OrdinalIgnoreCase))
        {
            if (!context.Request.Headers.TryGetValue("X-DeviceId", out var deviceIdHeader) ||
                !context.Request.Headers.TryGetValue("X-Device-Token", out var tokenHeader))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsync("Yêu cầu thiếu Header X-DeviceId hoặc X-Device-Token.");
                return;
            }

            string deviceId = deviceIdHeader.ToString().Trim();
            string rawToken = tokenHeader.ToString().Trim();

            if (string.IsNullOrEmpty(deviceId) || string.IsNullOrEmpty(rawToken))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsync("Header xác thực thiết bị không được để trống.");
                return;
            }

            // [KHẮC PHỤC TRIỆT ĐỂ P0-1]: ĐỒNG BỘ CHỮ THƯỜNG LOWERCASE CHO MÃ BĂM TOKEN THIẾT BỊ
            using var sha = SHA256.Create();
            string computedHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(rawToken))).ToLowerInvariant();

            string cacheKey = $"auth:dev:{deviceId}";
            if (!cache.TryGetValue<CachedDeviceAuthInfo>(cacheKey, out var authInfo))
            {
                var device = await db.DeviceRegistrations
                    .AsNoTracking()
                    .FirstOrDefaultAsync(d => d.Id == deviceId);

                if (device == null || !device.IsActive)
                {
                    _logger.LogWarning("Xác thực thất bại: Thiết bị {DeviceId} không tồn tại hoặc đã bị thu hồi quyền.", deviceId);
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    await context.Response.WriteAsync("Thiết bị không hợp lệ hoặc đã bị khóa.");
                    return;
                }

                authInfo = new CachedDeviceAuthInfo(device.DeviceTokenHash, device.IsActive);
                var entryOptions = new MemoryCacheEntryOptions()
                    .SetAbsoluteExpiration(TimeSpan.FromMinutes(5))
                    .SetSize(1);
                cache.Set(cacheKey, authInfo, entryOptions);
            }

            if (!authInfo!.IsActive)
            {
                _logger.LogWarning("Thiết bị {DeviceId} đã bị vô hiệu hóa trong CSDL.", deviceId);
                context.Response.StatusCode = StatusCodes.Status403Forbidden;
                await context.Response.WriteAsync("Thiết bị đã bị vô hiệu hóa.");
                return;
            }

            if (!CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(computedHash),
                Encoding.UTF8.GetBytes(authInfo.DeviceTokenHash)))
            {
                _logger.LogWarning("Xác thực thất bại: Token của thiết bị {DeviceId} không khớp.", deviceId);
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsync("Token thiết bị không hợp lệ.");
                return;
            }

            context.Items["ValidatedDeviceId"] = deviceId;
        }

        await _next(context);
    }
}
