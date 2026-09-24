using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.Core.DTOs;
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
    private readonly ILogger<TelemetryController> _logger;

    public TelemetryController(
        CareAiDbContext db,
        TelemetryEngine telemetryEngine,
        ClinicalDiagnosticEngine clinicalEngine,
        ILogger<TelemetryController> logger)
    {
        _db = db;
        _telemetryEngine = telemetryEngine;
        _clinicalEngine = clinicalEngine;
        _logger = logger;
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

        var (processedCount, message) = await _telemetryEngine.ProcessBatchLaneAsync(validatedDeviceId, batch, ct);

        // Kiểm tra lâm sàng theo thời gian thực cho các mẫu nhịp tim
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
}
