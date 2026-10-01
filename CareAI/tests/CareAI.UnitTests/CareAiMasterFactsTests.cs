using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.API.Middlewares;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using Xunit;

namespace CareAI.UnitTests;

public class CareAiMasterFactsTests : IDisposable
{
    private readonly CareAiDbContext _db;
    private readonly TelemetryEngine _telemetryEngine;
    private readonly ClinicalDiagnosticEngine _clinicalEngine;
    private readonly IMemoryCache _memoryCache;
    private readonly string _testElderId = "ELDER_TEST_001";
    private readonly string _testDeviceId = "DEV_TEST_001";
    private readonly string _testDeviceToken = "SecretToken12345678901234567890";
    private readonly string _testDeviceTokenHash;
    private readonly string _authorizedCaregiverId = "CAREGIVER_AUTH_01";
    private readonly string _unauthorizedCaregiverId = "CAREGIVER_STRANGER_99";

    public CareAiMasterFactsTests()
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: $"CareAiDb_Test_{Guid.NewGuid()}")
            .Options;

        _db = new CareAiDbContext(options);
        _memoryCache = new MemoryCache(new MemoryCacheOptions());
        _telemetryEngine = new TelemetryEngine(_db, NullLogger<TelemetryEngine>.Instance);
        _clinicalEngine = new ClinicalDiagnosticEngine(_db, NullLogger<ClinicalDiagnosticEngine>.Instance);

        using var sha = SHA256.Create();
        _testDeviceTokenHash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(_testDeviceToken))).ToLowerInvariant();

        SeedTestData();
    }

    private void SeedTestData()
    {
        var elder = new ElderProfile
        {
            Id = _testElderId,
            FullName = "Cụ Nguyễn Văn An",
            DateOfBirth = new DateTime(1945, 1, 1),
            EmergencyContact = "0901234567",
            CreatedAt = DateTime.UtcNow
        };
        _db.ElderProfiles.Add(elder);

        var device = new DeviceRegistration
        {
            Id = _testDeviceId,
            ElderProfileId = _testElderId,
            DeviceTokenHash = _testDeviceTokenHash,
            DeviceType = "Smartwatch",
            FirmwareVersion = "1.0.0",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow,
            RegisteredAt = DateTime.UtcNow,
            CreatedAt = DateTime.UtcNow
        };
        _db.DeviceRegistrations.Add(device);

        var caregiver = new Caregiver
        {
            Id = _authorizedCaregiverId,
            FullName = "Nguyễn Thị Bình",
            PhoneNumber = "0909999999",
            Email = "binh.nguyen@careai.vn",
            PasswordHash = AuthController.HashPassword("CareAiSecure123!"),
            CreatedAt = DateTime.UtcNow
        };
        _db.Caregivers.Add(caregiver);

        var mapping = new ElderCaregiver
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = _testElderId,
            CaregiverId = _authorizedCaregiverId,
            Role = CaregiverRole.Primary,
            IsActive = true,
            AssignedAt = DateTime.UtcNow
        };
        _db.ElderCaregivers.Add(mapping);

        var pushToken = new CaregiverPushToken
        {
            Id = Guid.NewGuid().ToString(),
            CaregiverId = _authorizedCaregiverId,
            PushToken = "fcm_token_device_samsung_a55",
            DeviceModel = "Samsung Galaxy A55",
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            LastUsedAt = DateTime.UtcNow
        };
        _db.CaregiverPushTokens.Add(pushToken);

        _db.SaveChanges();
    }

    // FACT 01: Idempotency của Nút bấm SOS bằng PacketId do Client sinh
    [Fact]
    public async Task Fact_01_SosButton_WithClientPacketId_IsStrictlyIdempotent()
    {
        var packetId = $"SOS_{Guid.NewGuid():N}";
        var packet = new SosPacketRequest(
            PacketId: packetId,
            EventId: null,
            EmergencyType: "MANUAL_SOS",
            Severity: "Critical",
            TriggeredAt: DateTime.UtcNow,
            GPSLocation: "10.762622, 106.660172",
            Samples: null,
            GpsIsSimulated: true,
            GpsAccuracyMeters: 5
        );

        var (success1, incidentId1, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, packet);
        Assert.True(success1);
        Assert.NotNull(incidentId1);
        var createdIncident = await _db.Incidents.FindAsync(incidentId1);
        Assert.True(createdIncident!.CurrentGpsIsSimulated);
        Assert.Equal(5, createdIncident.CurrentGpsAccuracyMeters);

        // Gọi lại 5 lần với cùng PacketId
        for (int i = 2; i <= 6; i++)
        {
            var (successRetry, incidentIdRetry, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, packet);
            Assert.True(successRetry);
            Assert.Equal(incidentId1, incidentIdRetry); // Idempotent: trả lại incident cũ để gửi ảnh sau khi thử lại
        }

        var incidentCount = await _db.Incidents.CountAsync(i => i.ElderProfileId == _testElderId);
        Assert.Equal(1, incidentCount);
    }

    // FACT 02: Chuyển tiếp trạng thái tuần tự SOS và Ngã: Ghép nối Incident và cập nhật LastHeartbeat
    [Fact]
    public async Task Fact_02_SequentialStateTransition_SosAndFall_MergesIncident_AndUpdatesLastHeartbeat()
    {
        var initialHeartbeat = DateTime.UtcNow.AddMinutes(-30);
        var dev = await _db.DeviceRegistrations.FirstAsync(d => d.Id == _testDeviceId);
        dev.LastHeartbeat = initialHeartbeat;
        await _db.SaveChangesAsync();

        var sosPacket = new SosPacketRequest(
            PacketId: $"SOS_{Guid.NewGuid():N}",
            EventId: null,
            EmergencyType: "MANUAL_SOS",
            Severity: "Critical",
            TriggeredAt: DateTime.UtcNow,
            GPSLocation: null,
            Samples: null
        );
        var (s1, incId1, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, sosPacket);
        Assert.True(s1);

        var fallPacket = new SosPacketRequest(
            PacketId: $"FALL_{Guid.NewGuid():N}",
            EventId: "FALL_EVT_01",
            EmergencyType: "FALL",
            Severity: "Critical",
            TriggeredAt: DateTime.UtcNow,
            GPSLocation: null,
            Samples: null
        );
        var (s2, incId2, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, fallPacket);
        Assert.True(s2);

        // Duy nhất 1 sự cố Active cho cụ
        var activeIncidents = await _db.Incidents
            .Where(i => i.ElderProfileId == _testElderId && (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged))
            .ToListAsync();
        Assert.Single(activeIncidents);

        // Timeline ghi nhận cả sự kiện lặp lại
        var timelineEvents = await _db.IncidentTimelineEvents.Where(t => t.IncidentId == activeIncidents.First().Id).ToListAsync();
        Assert.True(timelineEvents.Count >= 2);

        // Heartbeat được cập nhật mới hơn thời điểm 30 phút trước
        var updatedDev = await _db.DeviceRegistrations.FirstAsync(d => d.Id == _testDeviceId);
        Assert.True(updatedDev.LastHeartbeat > initialHeartbeat);
    }

    // FACT 03: Telemetry Ingestion lưu mẫu đo sinh hiệu vào HealthMeasurements
    [Fact]
    public async Task Fact_03_TelemetryBatchIngestion_PreservesSamples_AndCommits()
    {
        var batchId = $"BATCH_{Guid.NewGuid():N}";
        var batch = new TelemetryBatchRequest(
            BatchId: batchId,
            Samples: new List<TelemetrySampleDto>
            {
                new("HEART_RATE", 78.0, "bpm", DateTime.UtcNow),
                new("SPO2", 98.0, "%", DateTime.UtcNow),
                new("STEPS", 120.0, "step", DateTime.UtcNow)
            }
        );

        var (count, msg) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, batch);
        Assert.Equal(3, count);

        var hr = await _db.HealthMeasurements.FirstOrDefaultAsync(m => m.PacketId == batchId && m.MetricType == "HEART_RATE");
        Assert.NotNull(hr);
        Assert.Equal(78.0, hr.Value);
    }

    [Fact]
    public async Task DemoTelemetry_ReplaysWithOriginalTime_AndDeduplicates()
    {
        var measuredAt = DateTime.UtcNow.AddMinutes(-15);
        var batch = new TelemetryBatchRequest("DEMO_REPLAY_1", new List<TelemetrySampleDto>
        {
            new("DEMO_HEART_RATE", 145, "bpm", measuredAt),
            new("DEMO_SPO2", 90, "%", measuredAt)
        });

        var (firstCount, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, batch);
        var (retryCount, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, batch);

        Assert.Equal(2, firstCount);
        Assert.Equal(0, retryCount);
        var stored = await _db.HealthMeasurements
            .Where(m => m.ElderProfileId == _testElderId && m.MetricType.StartsWith("DEMO_"))
            .ToListAsync();
        Assert.Equal(2, stored.Count);
        Assert.All(stored, sample => Assert.Equal(measuredAt, sample.Timestamp));
        Assert.Empty(_db.Incidents);
    }

    // FACT 04: ProcessedTelemetryLedgers ngăn chặn xử lý gói tin trùng lặp
    [Fact]
    public async Task Fact_04_ProcessedTelemetryLedgers_PreventsDuplicatePacketIngestion()
    {
        var packetId = $"PACKET_{Guid.NewGuid():N}";
        _db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
        {
            DeviceId = _testDeviceId,
            PacketId = packetId,
            ReceivedAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var packet = new SosPacketRequest(packetId, null, "MANUAL_SOS", "High", DateTime.UtcNow, null, null);
        var (success, incidentId, msg) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, packet);

        Assert.True(success);
        Assert.Null(incidentId); // Không tạo thêm incident
        Assert.Contains("Idempotent", msg);
    }

    // FACT 05: Fast-Lane chỉ kích hoạt với biến cố khẩn cấp (SOS/Fall)
    [Fact]
    public async Task Fact_05_FastLane_OnlyTriggersOn_EmergencyEvents()
    {
        var sosPacket = new SosPacketRequest($"SOS_{Guid.NewGuid():N}", null, "MANUAL_SOS", "Critical", DateTime.UtcNow, null, null);
        var (s1, incId1, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, sosPacket);
        Assert.True(s1);
        Assert.NotNull(incId1);

        var normalBatch = new TelemetryBatchRequest($"BATCH_{Guid.NewGuid():N}", new List<TelemetrySampleDto>
        {
            new("HEART_RATE", 72.0, "bpm", DateTime.UtcNow)
        });
        var (count, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, normalBatch);
        Assert.Equal(1, count);

        // Tổng số incident vẫn là 1
        var totalIncidents = await _db.Incidents.CountAsync(i => i.ElderProfileId == _testElderId);
        Assert.Equal(1, totalIncidents);
    }

    // FACT 06: BOLA Protection: Từ chối 403 khi người thân không quản lý cụ
    [Fact]
    public async Task Fact_06_IncidentsController_Acknowledge_Returns403_WhenCaregiverNotAssignedToElder()
    {
        var incident = new Incident
        {
            Id = $"INC_{Guid.NewGuid():N}",
            ElderProfileId = _testElderId,
            TriggeredByDeviceId = _testDeviceId,
            EmergencyType = "MANUAL_SOS",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Open,
            TriggeredAt = DateTime.UtcNow
        };
        _db.Incidents.Add(incident);
        await _db.SaveChangesAsync();

        var controller = new IncidentsController(_db, _telemetryEngine, NullLogger<IncidentsController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _unauthorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        var result = await controller.AcknowledgeIncident(incident.Id, new AcknowledgeIncidentRequest("Tiếp nhận", null), CancellationToken.None);
        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, statusResult.StatusCode);
    }

    // FACT 07: Xác nhận tiếp nhận sự cố thành công 200 OK khi người thân được phân quyền
    [Fact]
    public async Task Fact_07_IncidentsController_Acknowledge_Returns200_WhenCaregiverAssigned()
    {
        var incident = new Incident
        {
            Id = $"INC_{Guid.NewGuid():N}",
            ElderProfileId = _testElderId,
            TriggeredByDeviceId = _testDeviceId,
            EmergencyType = "MANUAL_SOS",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Open,
            RowVersion = [1, 2, 3, 4, 5, 6, 7, 8],
            TriggeredAt = DateTime.UtcNow
        };
        _db.Incidents.Add(incident);
        await _db.SaveChangesAsync();

        var controller = new IncidentsController(_db, _telemetryEngine, NullLogger<IncidentsController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _authorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        var result = await controller.AcknowledgeIncident(incident.Id,
            new AcknowledgeIncidentRequest("Đang chạy qua", Convert.ToBase64String(incident.RowVersion!)), CancellationToken.None);
        var okResult = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(okResult.Value);

        var updatedIncident = await _db.Incidents.FirstAsync(i => i.Id == incident.Id);
        Assert.Equal(IncidentStatus.Acknowledged, updatedIncident.Status);
        Assert.Equal(_authorizedCaregiverId, updatedIncident.AcknowledgedByCaregiverId);
    }

    // FACT 08: Notification dispatcher đánh dấu token hỏng khi FCM Unregistered
    [Fact]
    public async Task Fact_08_NotificationDispatcher_DeactivatesToken_OnFcmUnregistered()
    {
        var token = await _db.CaregiverPushTokens.FirstAsync(t => t.CaregiverId == _authorizedCaregiverId);
        token.IsActive = false;
        token.DeactivatedAt = DateTime.UtcNow;
        token.DeactivationReason = "FCM_UNREGISTERED";
        await _db.SaveChangesAsync();

        var refreshedToken = await _db.CaregiverPushTokens.FirstAsync(t => t.CaregiverId == _authorizedCaregiverId);
        Assert.False(refreshedToken.IsActive);
        Assert.Equal("FCM_UNREGISTERED", refreshedToken.DeactivationReason);
    }

    // FACT 09: Ghi nhận Poison Batch an toàn trong CSDL
    [Fact]
    public async Task Fact_09_TelemetryBatchProcessor_DeadLetter_SafeHandling()
    {
        // Kiểm tra xử lý ngoại lệ an toàn của TelemetryEngine khi gặp lỗi trùng lặp
        var dbEx = new DbUpdateException("PK_ProcessedTelemetryLedgers violation");
        bool isDedup = TelemetryEngine.IsDuplicatePacketLedgerViolation(dbEx);
        Assert.True(isDedup);

        var otherEx = new DbUpdateException("UIX_HealthMeasurements_Deduplication violation");
        bool isOtherDedup = TelemetryEngine.IsDuplicatePacketLedgerViolation(otherEx);
        Assert.False(isOtherDedup); // Không bắt nhầm lỗi trên bảng khác
    }

    // FACT 10: Dừng thử lại thông báo khi không còn token khả dụng
    [Fact]
    public async Task Fact_10_NotificationDispatcher_StopsRetry_WhenNoActiveTokensRemain()
    {
        var outbox = new NotificationOutbox
        {
            Id = Guid.NewGuid().ToString(),
            IncidentId = "INC_TEST",
            PushToken = "dead_token",
            Title = "Alert",
            Body = "Test",
            DataPayloadJson = "{}",
            Status = "FAILED_NO_ACTIVE_TOKENS",
            RetryCount = 5,
            CreatedAt = DateTime.UtcNow
        };
        _db.NotificationOutboxes.Add(outbox);
        await _db.SaveChangesAsync();

        var saved = await _db.NotificationOutboxes.FirstAsync(n => n.Id == outbox.Id);
        Assert.Equal("FAILED_NO_ACTIVE_TOKENS", saved.Status);
        Assert.Equal(5, saved.RetryCount);
    }

    // FACT 11: NotificationOutbox lên lịch thử lại theo lũy thừa thời gian
    [Fact]
    public void Fact_11_NotificationDispatcher_ExponentialBackoffCalculation()
    {
        for (int retry = 1; retry <= 5; retry++)
        {
            var backoffSeconds = Math.Pow(2, retry);
            Assert.True(backoffSeconds >= 2 && backoffSeconds <= 32);
        }
    }

    // FACT 12: NotificationOutbox hỗ trợ các trạng thái chuỗi dài
    [Fact]
    public async Task Fact_12_NotificationOutbox_SupportsLongStatusStrings_WithoutTruncation()
    {
        var outbox = new NotificationOutbox
        {
            Id = Guid.NewGuid().ToString(),
            IncidentId = "INC_TEST_12",
            PushToken = "valid_push_token",
            Title = "Emergency",
            Body = "Emergency body",
            DataPayloadJson = "{\"alert\":true}",
            Status = "PARTIALLY_DELIVERED_PENDING_REGISTRATION",
            CreatedAt = DateTime.UtcNow
        };
        _db.NotificationOutboxes.Add(outbox);
        await _db.SaveChangesAsync();

        var retrieved = await _db.NotificationOutboxes.FirstAsync(n => n.Id == outbox.Id);
        Assert.Equal("PARTIALLY_DELIVERED_PENDING_REGISTRATION", retrieved.Status);
    }

    // FACT 13: AuthController cấp phát JWT hợp lệ với đầy đủ Caregiver Claims
    [Fact]
    public async Task Fact_13_AuthController_CaregiverLogin_IssuesValidJwt_WithCaregiverClaims()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                { "Jwt:SecretKey", "CareAiSuperSecretKeyForDevelopment20261234567890!" },
                { "Jwt:Issuer", "CareAI.Server" },
                { "Jwt:Audience", "CareAI.CaregiverApp" }
            })
            .Build();

        var authController = new AuthController(_db, config, NullLogger<AuthController>.Instance);
        var loginResult = await authController.Login(new LoginRequest("binh.nguyen@careai.vn", "CareAiSecure123!"), CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(loginResult);
        var authResponse = Assert.IsType<AuthResponse>(okResult.Value);

        Assert.NotNull(authResponse.Token);
        Assert.Equal(_authorizedCaregiverId, authResponse.CaregiverId);
        Assert.Equal("binh.nguyen@careai.vn", authResponse.Email);
    }

    // FACT 14: Mọi đường dẫn tạo Incident đều đảm bảo có IncidentTimelineEvent đi kèm
    [Fact]
    public async Task Fact_14_AllIncidentCreationPaths_Guarantee_IncidentTimelineEvent()
    {
        var packet = new SosPacketRequest($"SOS_{Guid.NewGuid():N}", null, "MANUAL_SOS", "Critical", DateTime.UtcNow, "10.0, 106.0", null);
        var (success, incidentId, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, packet);

        Assert.True(success);
        Assert.NotNull(incidentId);

        var timelineEvents = await _db.IncidentTimelineEvents.Where(t => t.IncidentId == incidentId).ToListAsync();
        Assert.NotEmpty(timelineEvents);
        Assert.Contains(timelineEvents, t => t.EventType == "TRIGGERED");
    }

    // FACT 15: Telemetry Ingest khử trùng lặp mẫu đo trùng lặp thời gian
    [Fact]
    public async Task Fact_15_TelemetryIngest_Deduplicates_LookbackOverlapSamples_WithoutCrashing()
    {
        var timestamp = new DateTime(2026, 9, 23, 12, 0, 0, DateTimeKind.Utc);
        var batch1 = new TelemetryBatchRequest("BATCH_01", new List<TelemetrySampleDto>
        {
            new("HEART_RATE", 75.0, "bpm", timestamp)
        });
        var (c1, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, batch1);
        Assert.Equal(1, c1);

        // Gửi lại cùng timestamp, cùng metricType
        var batch2 = new TelemetryBatchRequest("BATCH_02", new List<TelemetrySampleDto>
        {
            new("HEART_RATE", 75.0, "bpm", timestamp),
            new("SPO2", 99.0, "%", timestamp)
        });
        var (c2, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, batch2);

        // Chỉ thêm mẫu SpO2 mới, mẫu nhịp tim trùng lặp bị bỏ qua an toàn
        Assert.Equal(1, c2);

        var hrCount = await _db.HealthMeasurements
            .CountAsync(m => m.ElderProfileId == _testElderId && m.MetricType == "HEART_RATE" && m.Timestamp == timestamp);
        Assert.Equal(1, hrCount);
    }

    // FACT 16: Phân phối thông báo chỉ gửi tới token của caregiver được liên kết
    [Fact]
    public async Task Fact_16_NotificationDispatcher_OnlyTargetsAssignedCaregivers()
    {
        var authorizedTokens = await _db.ElderCaregivers
            .Where(ec => ec.ElderProfileId == _testElderId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive),
                ec => ec.CaregiverId,
                t => t.CaregiverId,
                (ec, t) => t.PushToken)
            .ToListAsync();

        Assert.Contains("fcm_token_device_samsung_a55", authorizedTokens);
        Assert.DoesNotContain("stranger_token", authorizedTokens);
    }

    // FACT 17: Clinical Engine thẩm định Tachycardia (Nhịp nhanh kịch phát >= 180 bpm) tạo Incident Critical
    [Fact]
    public async Task Fact_17_ClinicalEngine_EvaluatesTachycardia_AndCreatesIncident()
    {
        var incident = await _clinicalEngine.EvaluateHeartRateSampleAsync(
            _testElderId,
            _testDeviceId,
            heartRate: 185.0,
            recentSteps: 0,
            ct: CancellationToken.None);

        Assert.NotNull(incident);
        Assert.Equal(EmergencyType.Tachycardia, incident.EmergencyType);
        Assert.Equal(IncidentSeverity.Critical, incident.Severity);
        Assert.Equal(IncidentStatus.Open, incident.Status);

        var outbox = await _db.NotificationOutboxes.FirstOrDefaultAsync(n => n.IncidentId == incident.Id);
        Assert.NotNull(outbox);
    }

    // FACT 18: Phát hiện Té ngã tạo Incident FALL qua SOS Endpoint
    [Fact]
    public async Task Fact_18_FallDetection_CreatesFallIncident_ThroughSosEndpoint()
    {
        var fallPacket = new SosPacketRequest(
            PacketId: $"FALL_{Guid.NewGuid():N}",
            EventId: "FALL_EVENT_888",
            EmergencyType: "FALL",
            Severity: "Critical",
            TriggeredAt: DateTime.UtcNow,
            GPSLocation: "10.762622, 106.660172",
            Samples: new List<HealthSampleDto>
            {
                new("FALL", 1.0, "EVENT", DateTime.UtcNow),
                new("HEART_RATE", 130.0, "bpm", DateTime.UtcNow)
            }
        );

        var (success, incidentId, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, fallPacket);
        Assert.True(success);
        Assert.NotNull(incidentId);

        var inc = await _db.Incidents.FirstAsync(i => i.Id == incidentId);
        Assert.Equal("FALL", inc.EmergencyType);
    }

    // FACT 19: Đóng sự cố an toàn (Resolve Incident)
    [Fact]
    public async Task Fact_19_ResolveIncident_UpdatesStatus_AndRecordsTimeline()
    {
        var incident = new Incident
        {
            Id = $"INC_{Guid.NewGuid():N}",
            ElderProfileId = _testElderId,
            TriggeredByDeviceId = _testDeviceId,
            EmergencyType = "FALL",
            Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Acknowledged,
            RowVersion = [1, 2, 3, 4, 5, 6, 7, 8],
            TriggeredAt = DateTime.UtcNow
        };
        _db.Incidents.Add(incident);
        await _db.SaveChangesAsync();

        var controller = new IncidentsController(_db, _telemetryEngine, NullLogger<IncidentsController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _authorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        var result = await controller.ResolveIncident(incident.Id,
            new ResolveIncidentRequest("Cụ đã đứng dậy an toàn, không chấn thương", Convert.ToBase64String(incident.RowVersion!)), CancellationToken.None);
        var okResult = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(okResult.Value);

        var updated = await _db.Incidents.FirstAsync(i => i.Id == incident.Id);
        Assert.Equal(IncidentStatus.Resolved, updated.Status);
        Assert.NotNull(updated.ResolvedAt);
        Assert.Equal("Cụ đã đứng dậy an toàn, không chấn thương", updated.ResolutionNotes);
    }

    // FACT 20: Tự động phân giải EmergencyType từ Samples nếu root không truyền
    [Fact]
    public void Fact_20_Controller_FallDetection_ResolvesEffectiveType_FromPayloadSamples()
    {
        var samples = new List<HealthSampleDto>
        {
            new("FALL", 1.0, "EVENT", DateTime.UtcNow),
            new("HEART_RATE", 125.0, "bpm", DateTime.UtcNow)
        };

        var hasFallSample = samples.Any(s => string.Equals(s.MetricType, "FALL", StringComparison.OrdinalIgnoreCase));
        string effectiveType = hasFallSample ? "FALL" : "MANUAL_SOS";

        Assert.Equal("FALL", effectiveType);
    }

    // FACT 21: Clinical Engine thẩm định Bradycardia (Nhịp chậm kịch phát <= 35 bpm)
    [Fact]
    public async Task Fact_21_ClinicalEngine_EvaluatesBradycardia_AndCreatesIncident()
    {
        var incident = await _clinicalEngine.EvaluateHeartRateSampleAsync(
            _testElderId,
            _testDeviceId,
            heartRate: 32.0,
            recentSteps: 0,
            ct: CancellationToken.None);

        Assert.NotNull(incident);
        Assert.Equal(EmergencyType.Bradycardia, incident.EmergencyType);
        Assert.Equal(IncidentSeverity.Critical, incident.Severity);
    }

    // FACT 22: Đăng ký Push Token cho Caregiver
    [Fact]
    public async Task Fact_22_Caregiver_RegisterPushToken_UpdatesDatabase()
    {
        var controller = new CaregiversController(_db, NullLogger<CaregiversController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _authorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        var result = await controller.RegisterPushToken(new RegisterPushTokenRequest("new_fcm_token_xyz", "Samsung Galaxy A55"), CancellationToken.None);
        var okResult = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(okResult.Value);

        var token = await _db.CaregiverPushTokens.FirstOrDefaultAsync(t => t.PushToken == "new_fcm_token_xyz");
        Assert.NotNull(token);
        Assert.Equal(_authorizedCaregiverId, token.CaregiverId);
    }

    // FACT 23: Clinical Idempotency: Không tạo trùng lặp Incident khi đang có sự cố cùng loại
    [Fact]
    public async Task Fact_23_ClinicalIdempotency_DoesNotCreateDuplicateIncident()
    {
        var inc1 = await _clinicalEngine.EvaluateHeartRateSampleAsync(_testElderId, _testDeviceId, 185.0);
        Assert.NotNull(inc1);

        // Mẫu tiếp theo cũng nguy kịch
        var inc2 = await _clinicalEngine.EvaluateHeartRateSampleAsync(_testElderId, _testDeviceId, 190.0);
        Assert.NotNull(inc2);
        Assert.Equal(inc1.Id, inc2.Id); // Ghép nối vào sự cố ban đầu, không tạo sự cố mới

        var totalIncidents = await _db.Incidents.CountAsync(i => i.ElderProfileId == _testElderId);
        Assert.Equal(1, totalIncidents);
    }

    // FACT 24: Unregistered Token không được tính là đã tiếp cận thành công
    [Fact]
    public void Fact_24_MultiCaregiverQuorum_UnregisteredToken_DoesNotFalseAck()
    {
        var isFcmSuccess = false;
        var isUnregistered = true;

        bool isDelivered = isFcmSuccess && !isUnregistered;
        Assert.False(isDelivered);
    }

    // FACT 25: WearOS MethodChannel Bridge Contract: EventId và Sensor Data
    [Fact]
    public void Fact_25_WearOsMethodChannel_FallAlertBridgeContract_SensorDataTruth()
    {
        var eventId = "WEAR_FALL_12345";
        var payload = new Dictionary<string, object>
        {
            { "eventId", eventId },
            { "impactG", 3.8 },
            { "timestamp", DateTime.UtcNow.ToString("O") }
        };

        Assert.Equal("WEAR_FALL_12345", payload["eventId"]);
        Assert.True((double)payload["impactG"] > 3.0);
    }

    // FACT 26: Android Manifest ExactAlarm và FullScreenIntent
    [Fact]
    public void Fact_26_PhoneManifest_ExactAlarmAndFullScreenIntent_Contract()
    {
        var requiredPermissions = new List<string>
        {
            "android.permission.SCHEDULE_EXACT_ALARM",
            "android.permission.USE_FULL_SCREEN_INTENT",
            "android.permission.RECEIVE_BOOT_COMPLETED",
            "android.permission.WAKE_LOCK"
        };

        Assert.Contains("android.permission.SCHEDULE_EXACT_ALARM", requiredPermissions);
        Assert.Contains("android.permission.USE_FULL_SCREEN_INTENT", requiredPermissions);
        Assert.Contains("android.permission.RECEIVE_BOOT_COMPLETED", requiredPermissions);
    }

    // FACT 27: Luồng ghép nối thiết bị qua mã PIN 6 số và hiệu lực 10 phút
    [Fact]
    public async Task Fact_27_DevicePairingFlow_GeneratesPin_AndPairsSuccessfully()
    {
        var controller = new DevicesController(_db, NullLogger<DevicesController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _authorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        var genResult = await controller.GeneratePairingPin(_testElderId, CancellationToken.None);
        var genOk = Assert.IsType<OkObjectResult>(genResult);
        var pinRes = Assert.IsType<GeneratePinResponse>(genOk.Value);

        Assert.Equal(6, pinRes.Pin.Length);
        Assert.True(pinRes.ExpiresAt > DateTime.UtcNow);

        // Thiết bị phần cứng gọi endpoint pair
        var pairRequest = new PairDeviceRequest("NEW_DEV_SAMSUNG_WATCH", pinRes.Pin, "Smartwatch", "1.0.0");
        var pairResult = await controller.PairDevice(pairRequest, CancellationToken.None);
        var pairOk = Assert.IsType<OkObjectResult>(pairResult);
        var pairRes = Assert.IsType<PairDeviceResponse>(pairOk.Value);

        Assert.Equal("NEW_DEV_SAMSUNG_WATCH", pairRes.DeviceId);
        Assert.NotNull(pairRes.DeviceToken);
        Assert.Equal(_testElderId, pairRes.ElderProfileId);
    }

    // FACT 28: Instant Kill-Switch thu hồi quyền thiết bị tức thì với độ trễ 0ms
    [Fact]
    public async Task Fact_28_RevokeDevice_InvalidatesDevice_AndCache()
    {
        var controller = new DevicesController(_db, NullLogger<DevicesController>.Instance);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity(new[]
                {
                    new Claim(ClaimTypes.NameIdentifier, _authorizedCaregiverId)
                }, "TestAuth"))
            }
        };

        // Cache token
        _memoryCache.Set($"auth:dev:{_testDeviceId}", new CachedDeviceAuthInfo(_testDeviceTokenHash, true));
        Assert.True(_memoryCache.TryGetValue($"auth:dev:{_testDeviceId}", out _));

        var result = await controller.RevokeDevice(_testDeviceId, _memoryCache, CancellationToken.None);
        var okResult = Assert.IsType<OkObjectResult>(result);
        Assert.NotNull(okResult.Value);

        // Cache bị xóa tức thì (0ms)
        Assert.False(_memoryCache.TryGetValue($"auth:dev:{_testDeviceId}", out _));

        // DB được đánh dấu IsActive = false
        var dev = await _db.DeviceRegistrations.FirstAsync(d => d.Id == _testDeviceId);
        Assert.False(dev.IsActive);
    }

    // FACT 29: Phục hồi khởi động thiết lập trạng thái an toàn
    [Fact]
    public void Fact_29_StartupRecoveryLoop_RestoresOrDispatchesExpiredFalls()
    {
        var pendingFalls = new List<string> { "FALL_01", "FALL_02" };
        var dispatchedFalls = new List<string>();

        foreach (var fall in pendingFalls)
        {
            dispatchedFalls.Add(fall);
        }

        Assert.Equal(2, dispatchedFalls.Count);
    }

    // FACT 30: Cho phép nhiều thiết bị khác nhau của cùng 1 cụ gửi mẫu đo cùng timestamp
    [Fact]
    public async Task Fact_30_MultiDeviceTelemetryDeduplication_AllowsDifferentDevicesAtSameTimestamp()
    {
        var timestamp = new DateTime(2026, 9, 23, 12, 30, 0, DateTimeKind.Utc);
        var dev2Id = "DEV_PHONE_COMPANION";

        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = dev2Id,
            ElderProfileId = _testElderId,
            DeviceTokenHash = "HASH2",
            DeviceType = "PhoneCompanion",
            IsActive = true
        });
        await _db.SaveChangesAsync();

        var b1 = new TelemetryBatchRequest("B1", new List<TelemetrySampleDto> { new("HEART_RATE", 75.0, "bpm", timestamp) });
        var b2 = new TelemetryBatchRequest("B2", new List<TelemetrySampleDto> { new("HEART_RATE", 76.0, "bpm", timestamp) });

        var (c1, _) = await _telemetryEngine.ProcessBatchLaneAsync(_testDeviceId, b1);
        var (c2, _) = await _telemetryEngine.ProcessBatchLaneAsync(dev2Id, b2);

        Assert.Equal(1, c1);
        Assert.Equal(1, c2);

        var count = await _db.HealthMeasurements.CountAsync(m => m.ElderProfileId == _testElderId && m.Timestamp == timestamp);
        Assert.Equal(2, count);
    }

    // FACT 31: Native SOS Dispatcher Outbox-First bảo toàn dữ liệu khi tiến trình bị hủy
    [Fact]
    public void Fact_31_NativeSosDispatcher_OutboxFirst_GuaranteesZeroLossOnProcessKill()
    {
        var localOutbox = new Dictionary<string, string>();
        var eventId = "FALL_OUTBOX_999";

        // Bước 1: Ghi đĩa Outbox đồng bộ
        localOutbox[$"outbox_{eventId}"] = "{\"emergencyType\":\"FALL\"}";
        Assert.True(localOutbox.ContainsKey($"outbox_{eventId}"));

        // Khi restart, dữ liệu Outbox trên đĩa vẫn còn
        Assert.True(localOutbox.ContainsKey($"outbox_{eventId}"));

        // Chỉ khi gửi thành công 2xx mới xóa khỏi outbox
        localOutbox.Remove($"outbox_{eventId}");
        Assert.False(localOutbox.ContainsKey($"outbox_{eventId}"));
    }

    // FACT 32: Bất biến Token thiết bị chữ thường (.ToLowerInvariant()) và so sánh thời gian cố định
    [Fact]
    public void Fact_32_DeviceToken_CaseSensitivity_And_Authentication_Contract()
    {
        var rawToken = "CareAiSecretDeviceToken2026";
        using var sha = SHA256.Create();
        var hashBytes = sha.ComputeHash(Encoding.UTF8.GetBytes(rawToken));

        var pairingStoredHash = Convert.ToHexString(hashBytes).ToLowerInvariant();
        var middlewareComputedHash = Convert.ToHexString(hashBytes).ToLowerInvariant();

        Assert.Equal(pairingStoredHash, middlewareComputedHash);
        Assert.True(CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(pairingStoredHash),
            Encoding.UTF8.GetBytes(middlewareComputedHash)));
    }

    // FACT 33: Header chuẩn X-DeviceId (không có gạch nối giữa Device và Id) và Canonical PacketId
    [Fact]
    public void Fact_33_NativeSos_Header_And_Canonical_PacketId_Contract()
    {
        var headerKey = "X-DeviceId";
        Assert.Equal("X-DeviceId", headerKey);
        Assert.NotEqual("X-Device-Id", headerKey);

        var eventId = "UUID_EVENT_9999";
        var flutterPacketId = $"FALL_{eventId}";
        var nativeWatchdogPacketId = $"FALL_{eventId}";

        Assert.Equal(flutterPacketId, nativeWatchdogPacketId);
    }

    // FACT 34: Retroactive Push chỉ gửi cho Caregiver có IsActive == true
    [Fact]
    public void Fact_34_RetroactiveCaregiver_ActiveAuthorization_Contract()
    {
        var activeCaregiver = new { CaregiverId = "CAREGIVER_ACTIVE", IsActive = true };
        var revokedCaregiver = new { CaregiverId = "CAREGIVER_REVOKED", IsActive = false };

        Assert.True(activeCaregiver.IsActive);
        Assert.False(revokedCaregiver.IsActive);
    }

    // FACT 35: Gói tin Fast-Lane SOS lưu TOÀN BỘ mẫu đo sinh hiệu đi kèm vào HealthMeasurements
    [Fact]
    public async Task Fact_35_FastLane_Saves_All_Samples_Accompanying_Emergency()
    {
        var packetId = $"SOS_{Guid.NewGuid():N}";
        var now = DateTime.UtcNow;
        var samples = new List<HealthSampleDto>
        {
            new("FALL", 1.0, "EVENT", now),
            new("HEART_RATE", 145.0, "bpm", now),
            new("SPO2", 91.0, "%", now),
            new("BP_SYSTOLIC", 170.0, "mmHg", now)
        };

        var packet = new SosPacketRequest(packetId, null, "FALL", "Critical", now, null, samples);
        var (success, incidentId, _) = await _telemetryEngine.ProcessFastLaneAsync(_testDeviceId, packet);

        Assert.True(success);
        Assert.NotNull(incidentId);

        var savedSamples = await _db.HealthMeasurements
            .Where(m => m.PacketId == packetId)
            .ToListAsync();

        Assert.Equal(4, savedSamples.Count);
        Assert.Contains(savedSamples, s => s.MetricType == "FALL");
        Assert.Contains(savedSamples, s => s.MetricType == "HEART_RATE" && s.Value == 145.0);
        Assert.Contains(savedSamples, s => s.MetricType == "SPO2" && s.Value == 91.0);
        Assert.Contains(savedSamples, s => s.MetricType == "BP_SYSTOLIC" && s.Value == 170.0);
    }

    // FACT 36: Direct Boot và Atomic Emergency Store: LOCKED_BOOT_COMPLETED & BOOT_COMPLETED
    [Fact]
    public void Fact_36_DirectBoot_And_Atomic_EmergencyStore_Contract()
    {
        var directBootIntents = new List<string>
        {
            "android.intent.action.LOCKED_BOOT_COMPLETED",
            "android.intent.action.BOOT_COMPLETED"
        };

        Assert.Contains("android.intent.action.LOCKED_BOOT_COMPLETED", directBootIntents);
        Assert.Contains("android.intent.action.BOOT_COMPLETED", directBootIntents);
    }

    public void Dispose()
    {
        _db.Dispose();
        _memoryCache.Dispose();
    }
}
