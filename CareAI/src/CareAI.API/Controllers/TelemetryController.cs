using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using CareAI.Core.DTOs;
using CareAI.Infrastructure.Channels;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/telemetry")]
public class TelemetryController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly ITelemetryBatchQueue _queue;
    private readonly IMemoryCache _cache;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly ClinicalDiagnosticEngine _clinicalEngine;
    private readonly ILogger<TelemetryController> _logger;

    public TelemetryController(
        CareAiDbContext db,
        ITelemetryBatchQueue queue,
        IMemoryCache cache,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        ILogger<TelemetryController> logger)
    {
        _db = db;
        _queue = queue;
        _cache = cache;
        _telemetryEngine = telemetryEngine;
        _clinicalEngine = clinicalEngine;
        _logger = logger;
    }

    /// <summary>
    /// Tiếp nhận mẻ viễn trắc sinh hiệu qua hàng đợi phi khóa Non-Blocking Channel (Nhiệm vụ 1.2)
    /// Đảm bảo tốc độ phản hồi HTTP 202 Accepted trong dưới 15ms cho mẻ tối đa 500 mẫu
    /// </summary>
    [HttpPost("batch")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> IngestTelemetryBatch(
        [FromBody] TelemetryBatchRequest batch,
        CancellationToken ct)
    {
        var validatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(validatedDeviceId))
        {
            return Unauthorized(new { error = "Thiếu xác thực thiết bị (X-DeviceId)." });
        }

        if (batch.Samples == null || batch.Samples.Count == 0)
        {
            return BadRequest(new { error = "Danh sách mẫu đo sinh hiệu trống." });
        }

        // Ràng buộc giới hạn mẻ tối đa 500 mẫu theo chuẩn đặc tả Nhiệm vụ 1.2
        if (batch.Samples.Count > 500)
        {
            return BadRequest(new { error = $"Mẻ dữ liệu viễn trắc vượt quá giới hạn tối đa 500 mẫu (nhận {batch.Samples.Count} mẫu)." });
        }

        // Tối ưu hóa truy vấn danh tính cụ già qua IMemoryCache (5 phút) để đạt thời gian phản hồi < 5ms
        var cacheKey = $"dev_elder_{validatedDeviceId}";
        var elderProfileId = await _cache.GetOrCreateAsync(cacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            entry.Size = 1;
            var device = await _db.DeviceRegistrations.AsNoTracking()
                .FirstOrDefaultAsync(d => d.Id == validatedDeviceId && d.IsActive, ct);
            return device?.ElderProfileId;
        });

        if (string.IsNullOrEmpty(elderProfileId))
        {
            return Unauthorized(new { error = "Thiết bị không tồn tại trong hệ thống hoặc đã bị thu hồi quyền." });
        }

        var canonicalBatchId = string.IsNullOrWhiteSpace(batch.BatchId)
            ? $"BATCH_{Guid.NewGuid():N}"
            : batch.BatchId;

        var message = new TelemetryBatchMessage(
            DeviceId: validatedDeviceId,
            ElderProfileId: elderProfileId,
            BatchId: canonicalBatchId,
            Samples: batch.Samples,
            ReceivedAt: DateTime.UtcNow
        );

        // Đẩy vào hàng đợi bộ nhớ phi khóa RAM (Channel<T>)
        await _queue.EnqueueAsync(message, ct);

        return StatusCode(StatusCodes.Status202Accepted, new
        {
            status = "ACCEPTED",
            batchId = canonicalBatchId,
            sampleCount = batch.Samples.Count,
            queueDepth = _queue.Count,
            message = "Mẻ viễn trắc đã được tiếp nhận vào hàng đợi xử lý ngầm (Non-blocking Channel)."
        });
    }

    /// <summary>
    /// Endpoint tương thích ngược (Ingest Endpoint)
    /// Mặc định đưa vào Channel hàng đợi phi khóa (HTTP 202). Nếu ?sync=true sẽ xử lý đồng bộ (HTTP 201).
    /// </summary>
    [HttpPost("ingest")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> IngestTelemetry(
        [FromBody] TelemetryBatchRequest batch,
        [FromQuery] bool sync = false,
        CancellationToken ct = default)
    {
        if (!sync)
        {
            return await IngestTelemetryBatch(batch, ct);
        }

        // Luồng đồng bộ truyền thống
        var validatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(validatedDeviceId))
        {
            return Unauthorized(new { error = "Thiếu xác thực thiết bị." });
        }

        if (batch.Samples == null || batch.Samples.Count == 0)
        {
            return BadRequest(new { error = "Danh sách mẫu đo sinh hiệu trống." });
        }

        var device = await _db.DeviceRegistrations.AsNoTracking()
            .FirstOrDefaultAsync(d => d.Id == validatedDeviceId, ct);

        if (device == null)
        {
            return Unauthorized(new { error = "Thiết bị không tồn tại trong hệ thống." });
        }

        var (processedCount, message) = await _telemetryEngine.ProcessBatchLaneAsync(validatedDeviceId, batch, ct);

        foreach (var sample in batch.Samples)
        {
            if (string.Equals(sample.MetricType, "HEART_RATE", StringComparison.OrdinalIgnoreCase))
            {
                await _clinicalEngine.EvaluateHeartRateSampleAsync(
                    elderProfileId: device.ElderProfileId,
                    deviceId: validatedDeviceId,
                    heartRate: sample.Value,
                    recentSteps: 0,
                    ct: ct);
            }
        }

        return StatusCode(StatusCodes.Status201Created, new
        {
            status = "COMMITTED",
            batchId = batch.BatchId,
            processedCount,
            message
        });
    }

    /// <summary>
    /// Tiếp nhận tín hiệu nhịp đập thiết bị (Heartbeat Keep-Alive) phục vụ giám sát đường truyền (Nhiệm vụ 1.2)
    /// </summary>
    [HttpPost("heartbeat")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Heartbeat([FromBody] HeartbeatRequest request, CancellationToken ct)
    {
        var validatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(validatedDeviceId))
        {
            return Unauthorized(new { error = "Thiếu xác thực thiết bị (X-DeviceId)." });
        }

        var now = DateTime.UtcNow;
        var device = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == validatedDeviceId && d.IsActive, ct);

        if (device == null)
        {
            return Unauthorized(new { error = "Thiết bị không tồn tại hoặc đã bị vô hiệu hóa." });
        }

        device.LastHeartbeat = now;
        device.UpdatedAt = now;
        await _db.SaveChangesAsync(ct);

        return Ok(new
        {
            status = "ALIVE",
            deviceId = validatedDeviceId,
            batteryPercentage = request.BatteryPercentage,
            serverTime = now
        });
    }
}
