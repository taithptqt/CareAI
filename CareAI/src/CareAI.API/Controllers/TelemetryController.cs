using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using CareAI.Core.DTOs;
using CareAI.Infrastructure.Channels;
using CareAI.Core.Entities;
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
    private readonly UrgentTelemetryEngine _urgentEngine;
    private readonly ILogger<TelemetryController> _logger;

    public TelemetryController(
        CareAiDbContext db,
        ITelemetryBatchQueue? queue,
        IMemoryCache? cache,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        UrgentTelemetryEngine? urgentEngine = null,
        ILogger<TelemetryController>? logger = null)
    {
        _db = db;
        _queue = queue ?? new TelemetryBatchQueue();
        _cache = cache ?? new MemoryCache(new MemoryCacheOptions());
        _telemetryEngine = telemetryEngine;
        _clinicalEngine = clinicalEngine;
        _urgentEngine = urgentEngine ?? new UrgentTelemetryEngine(db, clinicalEngine);
        _logger = logger ?? Microsoft.Extensions.Logging.Abstractions.NullLogger<TelemetryController>.Instance;
    }

    public TelemetryController(
        CareAiDbContext db,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        UrgentTelemetryEngine urgentEngine,
        ILogger<TelemetryController> logger)
        : this(db, null, null, telemetryEngine, clinicalEngine, urgentEngine, logger)
    {
    }

    public TelemetryController(
        CareAiDbContext db,
        ITelemetryBatchQueue queue,
        IMemoryCache cache,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        ILogger<TelemetryController> logger)
        : this(db, queue, cache, telemetryEngine, clinicalEngine, null, logger)
    {
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
    /// Nhận một mẫu nhịp tim nguy kịch ngay khi đo, không chờ batch sync.
    /// </summary>
    [HttpPost("urgent-heart-rate")]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> IngestUrgentHeartRate(
        [FromBody] UrgentHeartRateRequest request, CancellationToken ct)
    {
        var validatedDeviceId = HttpContext.Items["ValidatedDeviceId"] as string;
        if (string.IsNullOrEmpty(validatedDeviceId))
            return Unauthorized(new { error = "Thiếu xác thực thiết bị." });

        if (string.IsNullOrWhiteSpace(request.PacketId) || request.PacketId.Length > 100)
            return BadRequest(new { error = "PacketId phải có từ 1 đến 100 ký tự." });
        if (!double.IsFinite(request.HeartRateBpm) || request.HeartRateBpm <= 0 || request.HeartRateBpm > 300 ||
            (request.HeartRateBpm < 180 && request.HeartRateBpm > 35))
            return BadRequest(new { error = "Đường khẩn chỉ nhận nhịp tim nguy kịch từ 1–35 hoặc 180–300 bpm." });
        var measuredAt = request.Timestamp.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(request.Timestamp, DateTimeKind.Utc)
            : request.Timestamp.ToUniversalTime();
        if (request.Timestamp == default || measuredAt > DateTime.UtcNow.AddMinutes(1))
            return BadRequest(new { error = "Thời điểm đo không hợp lệ." });

        var result = await _urgentEngine.ProcessHeartRateAsync(validatedDeviceId, request, ct);
        if (result.Status == "DEVICE_INACTIVE")
            return Unauthorized(new { error = "Thiết bị không còn hoạt động." });

        var response = new
        {
            status = result.Status,
            packetId = request.PacketId,
            incidentId = result.IncidentId
        };
        return result.Duplicate || result.Status == "STORED_STALE"
            ? Ok(response)
            : StatusCode(StatusCodes.Status201Created, response);
    }

    /// <summary>
    /// Tiếp nhận gói tin viễn trắc định kỳ theo mẻ (Batch-Lane Ingestion)

    /// </summary>
    [HttpPost("ingest")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> IngestTelemetry(
        [FromBody] TelemetryBatchRequest batch,
        CancellationToken ct = default,
        [FromQuery] bool sync = true)
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

        var acceptedSamples = new List<HealthMeasurement>();
        var (processedCount, message) = await _telemetryEngine.ProcessBatchLaneAsync(
            validatedDeviceId, batch, ct, acceptedSamples);

        // Kiểm tra lâm sàng theo thời gian thực cho các mẫu nhịp tim
        foreach (var sample in acceptedSamples.OrderBy(s => s.Timestamp))

        {
            if (sample.MetricType == "HEART_RATE" &&
                sample.Timestamp >= DateTime.UtcNow.AddMinutes(-2) &&
                sample.Timestamp <= DateTime.UtcNow.AddMinutes(1))
            {
                await _clinicalEngine.EvaluateHeartRateSampleAsync(
                    elderProfileId: device.ElderProfileId,
                    deviceId: validatedDeviceId,
                    heartRate: sample.Value,
                    ct: ct,
                    measuredAtUtc: sample.Timestamp);
            }
            else if (sample.MetricType == "SPO2")
            {
                await _clinicalEngine.EvaluateSpO2SampleAsync(
                    device.ElderProfileId, validatedDeviceId, sample.Value, sample.Timestamp, ct);
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
