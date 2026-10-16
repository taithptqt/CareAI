using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Channels;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;

namespace CareAI.Infrastructure.BackgroundWorkers;

/// <summary>
/// Background Service tiêu thụ hàng đợi viễn trắc phi khóa (Channel Consumer) theo mẻ
/// và tích hợp mạch cầu dao bảo vệ RAM (< 700MB)
/// Phục vụ Nhiệm vụ 1.3 theo Bản Kế hoạch Triển khai CareAI v111.0
/// </summary>
public class TelemetryBatchProcessorWorker : BackgroundService
{
    private readonly ITelemetryBatchQueue _queue;
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<TelemetryBatchProcessorWorker> _logger;

    private const int MaxBatchSize = 100;
    private const int BatchTimeoutMs = 1000;
    private const long RamThresholdBytes = 700L * 1024 * 1024; // 700 MB
    private const int MaxTransientRetries = 5;
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(5);

    public TelemetryBatchProcessorWorker(
        ITelemetryBatchQueue queue,
        IServiceProvider serviceProvider,
        ILogger<TelemetryBatchProcessorWorker> logger)
    {
        _queue = queue;
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[TELEMETRY-WORKER] Khởi động TelemetryBatchProcessorWorker. Tiêu thụ Channel mẻ {BatchSize}...", MaxBatchSize);

        var buffer = new List<TelemetryBatchMessage>(MaxBatchSize);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // Kiểm tra mạch cầu dao RAM (RAM Circuit Breaker)
                CheckMemoryPressure();

                buffer.Clear();

                // 1. Chờ ít nhất 1 phần tử từ Channel (tiết kiệm CPU tuyệt đối khi rảnh rỗi)
                if (!await _queue.Reader.WaitToReadAsync(stoppingToken))
                {
                    break;
                }

                // 2. Rút nhanh tất cả các gói tin đang có sẵn trong Channel lên tới MaxBatchSize
                while (buffer.Count < MaxBatchSize && _queue.Reader.TryRead(out var message))
                {
                    buffer.Add(message);
                }

                // 3. Xả mẻ xuống CSDL
                if (buffer.Count > 0)
                {
                    await ProcessBatchWithRetryAsync(buffer, stoppingToken);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                // Đảm bảo xả nốt các bản ghi còn sót lại trong buffer trước khi shutdown
                if (buffer.Count > 0)
                {
                    try
                    {
                        await ProcessBatchWithRetryAsync(buffer, CancellationToken.None);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "[TELEMETRY-WORKER-SHUTDOWN-ERR] Lỗi khi xả mẻ cuối trước khi shutdown.");
                    }
                }
                _logger.LogInformation("[TELEMETRY-WORKER] Đang dừng TelemetryBatchProcessorWorker theo yêu cầu hệ thống.");
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[TELEMETRY-WORKER-UNHANDLED] Lỗi bất ngờ trong vòng lặp tiêu thụ Channel viễn trắc.");
                await Task.Delay(1000, stoppingToken);
            }
        }
    }

    private void CheckMemoryPressure()
    {
        var allocated = GC.GetTotalMemory(forceFullCollection: false);
        if (allocated >= RamThresholdBytes)
        {
            _logger.LogWarning("[CIRCUIT-BREAKER] Bộ nhớ tiêu thụ đạt {RAM:F1} MB (vượt ngưỡng 700 MB). Kích hoạt Garbage Collection cưỡng bức...", (double)allocated / 1024 / 1024);
            GC.Collect(2, GCCollectionMode.Forced, blocking: true, compacting: true);
            var afterGc = GC.GetTotalMemory(forceFullCollection: false);
            _logger.LogInformation("[CIRCUIT-BREAKER] Sau khi giải phóng: Bộ nhớ giảm còn {RAM:F1} MB.", (double)afterGc / 1024 / 1024);
        }
    }

    private async Task ProcessBatchWithRetryAsync(List<TelemetryBatchMessage> batch, CancellationToken ct)
    {
        int retryCount = 0;

        while (retryCount < MaxTransientRetries)
        {
            try
            {
                using var scope = _serviceProvider.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
                var clinicalEngine = scope.ServiceProvider.GetRequiredService<ClinicalDiagnosticEngine>();
                var staleEngine = scope.ServiceProvider.GetService<DeviceStaleEngine>()
                    ?? new DeviceStaleEngine(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<DeviceStaleEngine>.Instance);

                var now = DateTime.UtcNow;
                int addedMeasurements = 0;
                var heartRateEvaluations = new List<(string ElderId, string DeviceId, double HeartRate, DateTime Timestamp)>();
                var spo2Evaluations = new List<(string ElderId, string DeviceId, double SpO2, DateTime Timestamp)>();

                foreach (var msg in batch)
                {
                    // 1. Khử trùng lặp Idempotency trên ProcessedTelemetryLedgers (Bất biến P0-3)
                    var existsLedger = await db.ProcessedTelemetryLedgers
                        .AnyAsync(l => l.DeviceId == msg.DeviceId && l.PacketId == msg.BatchId, ct);

                    if (existsLedger)
                    {
                        _logger.LogInformation("[BATCH-DEDUP] Bỏ qua mẻ viễn trắc đã được ghi nhận: Device={DeviceId}, BatchId={BatchId}", msg.DeviceId, msg.BatchId);
                        continue;
                    }

                    db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
                    {
                        DeviceId = msg.DeviceId,
                        PacketId = msg.BatchId,
                        ReceivedAt = now
                    });

                    // Cập nhật LastHeartbeat thiết bị
                    var device = await db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == msg.DeviceId, ct);
                    if (device != null)
                    {
                        device.LastHeartbeat = now;
                        device.UpdatedAt = now;
                    }

                    // 2. Thêm các mẫu đo sinh hiệu vào HealthMeasurements (tránh trùng lặp theo UIX_HealthMeasurements_Deduplication)
                    foreach (var sample in msg.Samples)
                    {
                        if (string.IsNullOrWhiteSpace(sample.MetricType) || !double.IsFinite(sample.Value) || sample.Value <= 0)
                        {
                            continue;
                        }
                        var timestamp = sample.Timestamp == default ? msg.ReceivedAt : sample.Timestamp;
                        var metricType = sample.MetricType.ToUpperInvariant();

                        var alreadyInTracker = db.ChangeTracker.Entries<HealthMeasurement>().Any(e =>
                            e.Entity.ElderProfileId == msg.ElderProfileId &&
                            e.Entity.DeviceId == msg.DeviceId &&
                            e.Entity.Timestamp == timestamp &&
                            e.Entity.MetricType == metricType);

                        if (!alreadyInTracker)
                        {
                            var existsMeasurement = await db.HealthMeasurements.AnyAsync(m =>
                                m.ElderProfileId == msg.ElderProfileId &&
                                m.DeviceId == msg.DeviceId &&
                                m.Timestamp == timestamp &&
                                m.MetricType == metricType, ct);

                            if (!existsMeasurement)
                            {
                                db.HealthMeasurements.Add(new HealthMeasurement
                                {
                                    ElderProfileId = msg.ElderProfileId,
                                    DeviceId = msg.DeviceId,
                                    PacketId = msg.BatchId,
                                    MetricType = metricType,
                                    Value = sample.Value,
                                    Unit = sample.Unit ?? (metricType == "HEART_RATE" ? "bpm" : "unit"),
                                    Timestamp = timestamp,
                                    RecordedAt = now
                                });
                                addedMeasurements++;
                            }
                        }

                        if (metricType == "HEART_RATE")
                        {
                            heartRateEvaluations.Add((msg.ElderProfileId, msg.DeviceId, sample.Value, timestamp));
                        }
                        else if (metricType == "SPO2")
                        {
                            spo2Evaluations.Add((msg.ElderProfileId, msg.DeviceId, sample.Value, timestamp));
                        }
                    }
                }

                // 3. Lưu xuống cơ sở dữ liệu
                try
                {
                    await db.SaveChangesAsync(ct);
                }
                catch (DbUpdateException ex) when (ex.InnerException is Microsoft.Data.SqlClient.SqlException sqlEx && (sqlEx.Number == 2601 || sqlEx.Number == 2627))
                {
                    _logger.LogWarning("[BATCH-DUPLICATE-KEY-SKIPPED] Bỏ qua mẫu đo trùng lặp đã tồn tại trong CSDL do va chạm khóa: {Message}", ex.Message);
                }

                _logger.LogInformation("[TELEMETRY-WORKER-COMMITTED] Đã xả thành công mẻ {BatchCount} gói tin ({MeasurementsCount} mẫu đo) vào Azure SQL.", batch.Count, addedMeasurements);

                // 4. Đánh giá lâm sàng thời gian thực cho các mẫu nhịp tim
                foreach (var eval in heartRateEvaluations)
                {
                    await clinicalEngine.EvaluateHeartRateSampleAsync(
                        elderProfileId: eval.ElderId,
                        deviceId: eval.DeviceId,
                        heartRate: eval.HeartRate,
                        recentSteps: 0,
                        ct: ct,
                        measuredAtUtc: eval.Timestamp);
                }

                // 5. Đánh giá lâm sàng thời gian thực cho các mẫu SpO2 (cửa sổ 20 phút cho mẻ viễn trắc)
                foreach (var eval in spo2Evaluations)
                {
                    await clinicalEngine.EvaluateSpO2SampleAsync(
                        elderProfileId: eval.ElderId,
                        deviceId: eval.DeviceId,
                        spo2: eval.SpO2,
                        measuredAtUtc: eval.Timestamp,
                        ct: ct,
                        maxBackfillAge: TimeSpan.FromMinutes(20));
                }

                // 6. Hướng 3: Tự động đóng sự cố STALE_OFFLINE khi thiết bị gửi lại viễn trắc thành công
                var elderIds = batch.Select(b => b.ElderProfileId).Where(id => !string.IsNullOrEmpty(id)).Distinct();
                foreach (var elderId in elderIds)
                {
                    await staleEngine.TryAutoResolveStaleIncidentAsync(elderId, now, ct);
                }

                return; // Thành công, thoát vòng lặp retry
            }
            catch (Exception ex) when (ex is DbUpdateException or Microsoft.Data.SqlClient.SqlException)
            {
                retryCount++;
                _logger.LogWarning(ex, "[TELEMETRY-WORKER-RETRY] Gặp lỗi tạm thời khi ghi mẻ CSDL (lần thử {Retry}/{Max}). Chờ {Delay}s...", retryCount, MaxTransientRetries, RetryDelay.TotalSeconds);

                if (retryCount >= MaxTransientRetries)
                {
                    _logger.LogCritical(ex, "[TELEMETRY-DEAD-LETTER] Mẻ {Count} gói tin viễn trắc thất bại quá 5 lần. Chuyển vào Dead Letter Batch Log để bảo toàn dữ liệu.", batch.Count);
                    // Dữ liệu được ghi log dead-letter để không chặn luồng các mẻ kế tiếp
                    return;
                }

                await Task.Delay(RetryDelay, ct);
            }
        }
    }
}
