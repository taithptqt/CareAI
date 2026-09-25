using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/telemetry")]
public class TelemetryController : ControllerBase
{
    private readonly CareAiDbContext _db;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly ClinicalDiagnosticEngine _clinicalEngine;
    private readonly UrgentTelemetryEngine _urgentEngine;
    private readonly ILogger<TelemetryController> _logger;

    public TelemetryController(
        CareAiDbContext db,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        UrgentTelemetryEngine urgentEngine,
        ILogger<TelemetryController> logger)
    {
        _db = db;
        _telemetryEngine = telemetryEngine;
        _clinicalEngine = clinicalEngine;
        _urgentEngine = urgentEngine;
        _logger = logger;
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
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> IngestTelemetry([FromBody] TelemetryBatchRequest batch, CancellationToken ct)
    {
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
        }

        return StatusCode(StatusCodes.Status201Created, new
        {
            status = "COMMITTED",
            batchId = batch.BatchId,
            processedCount,
            message
        });
    }
}
