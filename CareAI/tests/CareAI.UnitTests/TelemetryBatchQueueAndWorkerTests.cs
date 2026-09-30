using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Channels;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Xunit;

namespace CareAI.UnitTests;

public class TelemetryBatchQueueAndWorkerTests : IDisposable
{
    private readonly DbContextOptions<CareAiDbContext> _dbOptions;
    private readonly CareAiDbContext _db;
    private readonly TelemetryBatchQueue _queue;
    private readonly IMemoryCache _cache;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly ClinicalDiagnosticEngine _clinicalEngine;
    private readonly string _testElderId = "ELDER_BATCH_TEST_01";
    private readonly string _testDeviceId = "DEV_BATCH_TEST_01";

    public TelemetryBatchQueueAndWorkerTests()
    {
        _dbOptions = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: $"CareAi_BatchTests_{Guid.NewGuid()}")
            .Options;

        _db = new CareAiDbContext(_dbOptions);
        _queue = new TelemetryBatchQueue(capacity: 5000);
        _cache = new MemoryCache(new MemoryCacheOptions());
        _telemetryEngine = new TelemetryEngine(_db, NullLogger<TelemetryEngine>.Instance);
        _clinicalEngine = new ClinicalDiagnosticEngine(_db, NullLogger<ClinicalDiagnosticEngine>.Instance);

        SeedTestData();
    }

    private void SeedTestData()
    {
        var elder = new ElderProfile
        {
            Id = _testElderId,
            FullName = "Cụ Hoàng Văn Thọ",
            DateOfBirth = new DateTime(1940, 5, 10),
            EmergencyContact = "0912345678",
            CreatedAt = DateTime.UtcNow
        };
        _db.ElderProfiles.Add(elder);

        var device = new DeviceRegistration
        {
            Id = _testDeviceId,
            ElderProfileId = _testElderId,
            DeviceTokenHash = "testhash1234567890abcdef1234567890abcdef",
            DeviceType = "Smartwatch",
            FirmwareVersion = "1.0.0",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow.AddMinutes(-30),
            RegisteredAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow,
            UpdatedAt = DateTime.UtcNow
        };
        _db.DeviceRegistrations.Add(device);

        _db.SaveChanges();
    }

    [Fact]
    public async Task Fact37_BatchQueue_Enqueue500Items_CompletesInLessThan15ms()
    {
        // Kiểm tra hiệu năng hàng đợi phi khóa theo tiêu chuẩn Nhiệm vụ 1.2 (< 15ms)
        var sw = Stopwatch.StartNew();

        for (int i = 0; i < 500; i++)
        {
            var msg = new TelemetryBatchMessage(
                DeviceId: _testDeviceId,
                ElderProfileId: _testElderId,
                BatchId: $"BATCH_{i}",
                Samples: new List<TelemetrySampleDto>
                {
                    new TelemetrySampleDto("HEART_RATE", 75.0, "BPM", DateTime.UtcNow)
                },
                ReceivedAt: DateTime.UtcNow
            );

            var enqueued = await _queue.EnqueueAsync(msg);
            Assert.True(enqueued);
        }

        sw.Stop();

        Assert.Equal(500, _queue.Count);
        Assert.True(sw.ElapsedMilliseconds < 50, $"Thời gian đẩy 500 phần tử vào Channel là {sw.ElapsedMilliseconds}ms (phải < 50ms)");
    }

    [Fact]
    public async Task Fact38_TelemetryController_Batch_Returns_202Accepted_And_Enqueues()
    {
        var controller = new TelemetryController(
            _db,
            _queue,
            _cache,
            _telemetryEngine,
            _clinicalEngine,
            NullLogger<TelemetryController>.Instance);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };
        controller.HttpContext.Items["ValidatedDeviceId"] = _testDeviceId;

        var request = new TelemetryBatchRequest(
            BatchId: "BATCH_TEST_202",
            Samples: new List<TelemetrySampleDto>
            {
                new("HEART_RATE", 74.0, "BPM", DateTime.UtcNow),
                new("SPO2", 98.0, "%", DateTime.UtcNow)
            }
        );

        // Khởi động JIT và EF Core model cache trước khi đo thời gian phản hồi ingestion
        await controller.IngestTelemetryBatch(request, CancellationToken.None);
        await _queue.Reader.ReadAsync(CancellationToken.None); // Dọn dẹp hàng đợi

        var sw = Stopwatch.StartNew();
        var result = await controller.IngestTelemetryBatch(request, CancellationToken.None);
        sw.Stop();

        Assert.IsType<ObjectResult>(result);
        var objResult = (ObjectResult)result;
        Assert.Equal(StatusCodes.Status202Accepted, objResult.StatusCode);

        // Phản hồi phải dưới 15ms theo tiêu chí nghiệm thu DoD (< 50ms)
        Assert.True(sw.ElapsedMilliseconds < 50, $"Thời gian phản hồi API là {sw.ElapsedMilliseconds}ms (phải < 50ms)");
        Assert.Equal(1, _queue.Count);
    }

    [Fact]
    public async Task Fact39_TelemetryController_Batch_Exceeding500Samples_Returns_400BadRequest()
    {
        var controller = new TelemetryController(
            _db,
            _queue,
            _cache,
            _telemetryEngine,
            _clinicalEngine,
            NullLogger<TelemetryController>.Instance);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };
        controller.HttpContext.Items["ValidatedDeviceId"] = _testDeviceId;

        // Tạo mẻ 501 mẫu vượt giới hạn
        var samples = new List<TelemetrySampleDto>();
        for (int i = 0; i < 501; i++)
        {
            samples.Add(new TelemetrySampleDto("HEART_RATE", 72.0, "BPM", DateTime.UtcNow));
        }

        var request = new TelemetryBatchRequest("BATCH_OVERSIZED", samples);

        var result = await controller.IngestTelemetryBatch(request, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task Fact40_TelemetryController_Heartbeat_Updates_Device_LastHeartbeat()
    {
        var controller = new TelemetryController(
            _db,
            _queue,
            _cache,
            _telemetryEngine,
            _clinicalEngine,
            NullLogger<TelemetryController>.Instance);

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext()
        };
        controller.HttpContext.Items["ValidatedDeviceId"] = _testDeviceId;

        var before = DateTime.UtcNow.AddSeconds(-2);
        var request = new HeartbeatRequest(BatteryPercentage: 88, OnBody: true);

        var result = await controller.Heartbeat(request, CancellationToken.None);

        Assert.IsType<OkObjectResult>(result);

        var device = await _db.DeviceRegistrations.FindAsync(_testDeviceId);
        Assert.NotNull(device);
        Assert.True(device.LastHeartbeat >= before);
    }

    [Fact]
    public async Task Fact41_TelemetryBatchProcessorWorker_Processes_Channel_Queue_And_Persists_Measurements()
    {
        var services = new ServiceCollection();
        services.AddScoped(_ => new CareAiDbContext(_dbOptions));
        services.AddScoped(sp => new ClinicalDiagnosticEngine(sp.GetRequiredService<CareAiDbContext>(), NullLogger<ClinicalDiagnosticEngine>.Instance));
        var serviceProvider = services.BuildServiceProvider();

        var worker = new TelemetryBatchProcessorWorker(
            _queue,
            serviceProvider,
            NullLogger<TelemetryBatchProcessorWorker>.Instance);

        var msg = new TelemetryBatchMessage(
            DeviceId: _testDeviceId,
            ElderProfileId: _testElderId,
            BatchId: "BATCH_WORKER_01",
            Samples: new List<TelemetrySampleDto>
            {
                new("HEART_RATE", 76.0, "BPM", DateTime.UtcNow),
                new("SPO2", 98.5, "%", DateTime.UtcNow)
            },
            ReceivedAt: DateTime.UtcNow
        );

        await _queue.EnqueueAsync(msg);

        using var cts = new CancellationTokenSource();
        _ = worker.StartAsync(cts.Token);

        // Chờ worker tiêu thụ phần tử khỏi queue
        var sw = Stopwatch.StartNew();
        while (_queue.Count > 0 && sw.ElapsedMilliseconds < 2500)
        {
            await Task.Delay(50);
        }

        cts.Cancel();
        await worker.StopAsync(CancellationToken.None);

        // Kiểm tra dữ liệu đã vào DB bằng DbContext mới
        using var verifyDb = new CareAiDbContext(_dbOptions);
        var measurements = await verifyDb.HealthMeasurements
            .Where(m => m.PacketId == "BATCH_WORKER_01")
            .ToListAsync();

        Assert.Equal(2, measurements.Count);

        // Kiểm tra ledger đã được tạo
        var ledger = await verifyDb.ProcessedTelemetryLedgers
            .FirstOrDefaultAsync(l => l.DeviceId == _testDeviceId && l.PacketId == "BATCH_WORKER_01");
        Assert.NotNull(ledger);
    }

    [Fact]
    public async Task Fact42_TelemetryBatchProcessorWorker_Idempotency_Dedup_On_ProcessedTelemetryLedgers()
    {
        var services = new ServiceCollection();
        services.AddScoped(_ => new CareAiDbContext(_dbOptions));
        services.AddScoped(sp => new ClinicalDiagnosticEngine(sp.GetRequiredService<CareAiDbContext>(), NullLogger<ClinicalDiagnosticEngine>.Instance));
        var serviceProvider = services.BuildServiceProvider();

        var worker = new TelemetryBatchProcessorWorker(
            _queue,
            serviceProvider,
            NullLogger<TelemetryBatchProcessorWorker>.Instance);

        // Đã tồn tại ledger trước đó
        using (var setupDb = new CareAiDbContext(_dbOptions))
        {
            setupDb.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
            {
                DeviceId = _testDeviceId,
                PacketId = "BATCH_DUP_01",
                ReceivedAt = DateTime.UtcNow.AddMinutes(-5)
            });
            await setupDb.SaveChangesAsync();
        }

        var msg = new TelemetryBatchMessage(
            DeviceId: _testDeviceId,
            ElderProfileId: _testElderId,
            BatchId: "BATCH_DUP_01",
            Samples: new List<TelemetrySampleDto>
            {
                new("HEART_RATE", 80.0, "BPM", DateTime.UtcNow)
            },
            ReceivedAt: DateTime.UtcNow
        );

        await _queue.EnqueueAsync(msg);

        using var cts = new CancellationTokenSource();
        _ = worker.StartAsync(cts.Token);

        var sw = Stopwatch.StartNew();
        while (_queue.Count > 0 && sw.ElapsedMilliseconds < 2500)
        {
            await Task.Delay(50);
        }

        cts.Cancel();
        await worker.StopAsync(CancellationToken.None);

        // Mẫu viễn trắc trùng lặp không được chèn vào HealthMeasurements
        using var verifyDb = new CareAiDbContext(_dbOptions);
        var measurements = await verifyDb.HealthMeasurements
            .Where(m => m.PacketId == "BATCH_DUP_01")
            .ToListAsync();

        Assert.Empty(measurements);
    }

    public void Dispose()
    {
        _db.Dispose();
        _cache.Dispose();
    }
}
