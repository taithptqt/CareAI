using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using CareAI.Infrastructure.Data;

namespace CareAI.Infrastructure.BackgroundWorkers;

/// <summary>
/// DataRetentionBackgroundWorker: Background Service định kỳ dọn dẹp dữ liệu viễn trắc cũ (HealthMeasurements & ProcessedTelemetryLedgers)
/// Bảo vệ giới hạn dung lượng vật lý 2GB trên CSDL SQL Server.
/// ÁP DỤNG KỸ THUẬT CHUNKED BATCH DELETION (TOP 1000) ĐỂ TRÁNH KHÓA BẢNG (LOCK ESCALATION) GÂY NGHẼN LUỒNG CẤP CỨU.
/// </summary>
public class DataRetentionBackgroundWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<DataRetentionBackgroundWorker> _logger;
    private readonly TimeSpan _runInterval = TimeSpan.FromHours(24);
    private const int RetentionDays = 30;
    private const int BatchChunkSize = 1000;

    public DataRetentionBackgroundWorker(IServiceScopeFactory scopeFactory, ILogger<DataRetentionBackgroundWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[DataRetention] Khởi động DataRetentionBackgroundWorker. Chu kỳ: 24h, Lưu trữ tối đa: {Days} ngày.", RetentionDays);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
                if (!db.Database.IsSqlServer())
                {
                    await Task.Delay(_runInterval, stoppingToken);
                    continue;
                }
                var cutoff = DateTime.UtcNow.AddDays(-RetentionDays);

                // 1. DỌN BẢNG HealthMeasurements THEO MẺ (TOP 1000) CHỐNG LOCK ESCALATION
                int totalHealthDeleted = 0;
                while (!stoppingToken.IsCancellationRequested)
                {
                    int deleted = await db.Database.ExecuteSqlRawAsync(
                        @"DELETE TOP ({0}) FROM HealthMeasurements WHERE [Timestamp] < {1};",
                        new object[] { BatchChunkSize, cutoff }, stoppingToken);

                    totalHealthDeleted += deleted;
                    if (deleted < BatchChunkSize) break;
                    await Task.Delay(50, stoppingToken);
                }

                // 2. DỌN BẢNG ProcessedTelemetryLedgers THEO MẺ (TOP 1000)
                int totalLedgerDeleted = 0;
                while (!stoppingToken.IsCancellationRequested)
                {
                    int deleted = await db.Database.ExecuteSqlRawAsync(
                        @"DELETE TOP ({0}) FROM ProcessedTelemetryLedgers WHERE [ReceivedAt] < {1};",
                        new object[] { BatchChunkSize, cutoff }, stoppingToken);

                    totalLedgerDeleted += deleted;
                    if (deleted < BatchChunkSize) break;
                    await Task.Delay(50, stoppingToken);
                }

                _logger.LogInformation("[DataRetention-Success] Đã dọn dẹp {Health} bản ghi sinh hiệu và {Ledger} sổ cái quá {Days} ngày.",
                    totalHealthDeleted, totalLedgerDeleted, RetentionDays);
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                _logger.LogError(ex, "[DataRetention-Error] Lỗi trong quá trình dọn dẹp dữ liệu lưu trữ định kỳ.");
            }

            await Task.Delay(_runInterval, stoppingToken);
        }
    }
}
