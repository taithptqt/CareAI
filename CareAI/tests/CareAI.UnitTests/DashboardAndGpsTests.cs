using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Xunit;

namespace CareAI.UnitTests;

public class DashboardAndGpsTests : IDisposable
{
    private readonly CareAiDbContext _db;
    private readonly string _testElderId = "ELDER_DASH_001";
    private readonly string _authCaregiverId = "CAREGIVER_DASH_01";
    private readonly string _unauthCaregiverId = "CAREGIVER_DASH_99";

    public DashboardAndGpsTests()
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: $"CareAiDb_DashTest_{Guid.NewGuid()}")
            .Options;

        _db = new CareAiDbContext(options);
        SeedData();
    }

    private void SeedData()
    {
        var elder = new ElderProfile
        {
            Id = _testElderId,
            FullName = "Cụ Lê Thị Bình",
            DateOfBirth = new DateTime(1945, 5, 20),
            CreatedAt = DateTime.UtcNow
        };
        _db.ElderProfiles.Add(elder);

        var caregiverLink = new ElderCaregiver
        {
            CaregiverId = _authCaregiverId,
            ElderProfileId = _testElderId,
            IsActive = true
        };
        _db.ElderCaregivers.Add(caregiverLink);

        var now = DateTime.UtcNow;
        _db.HealthMeasurements.AddRange(
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P1",
                MetricType = "GPS_LAT",
                Value = 10.762622,
                Unit = "deg",
                Timestamp = now.AddMinutes(-5),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P2",
                MetricType = "GPS_LNG",
                Value = 106.660172,
                Unit = "deg",
                Timestamp = now.AddMinutes(-5),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P3",
                MetricType = "HEART_RATE",
                Value = 72,
                Unit = "bpm",
                Timestamp = now.AddHours(-10),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P4",
                MetricType = "HEART_RATE",
                Value = 88,
                Unit = "bpm",
                Timestamp = now.AddHours(-5),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P5",
                MetricType = "HEART_RATE",
                Value = 65,
                Unit = "bpm",
                Timestamp = now.AddMinutes(-30),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P6",
                MetricType = "BLOOD_PRESSURE_SYS",
                Value = 135,
                Unit = "mmHg",
                Timestamp = now.AddDays(-1),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P7",
                MetricType = "BLOOD_PRESSURE_DIA",
                Value = 85,
                Unit = "mmHg",
                Timestamp = now.AddDays(-1),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P8",
                MetricType = "SPO2",
                Value = 94,
                Unit = "%",
                Timestamp = now.AddHours(-3),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P9",
                MetricType = "SPO2",
                Value = 98,
                Unit = "%",
                Timestamp = now.AddMinutes(-10),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P10",
                MetricType = "STEPS",
                Value = 500,
                Unit = "steps",
                Timestamp = now,
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId,
                DeviceId = "DEV_01",
                PacketId = "P11",
                MetricType = "SLEEP",
                Value = 420,
                Unit = "minutes",
                Timestamp = now.Date.AddDays(-1).AddHours(22),
                RecordedAt = now
            }
        );

        _db.SaveChanges();
    }

    private DashboardController CreateController(string caregiverId)
    {
        var controller = new DashboardController(_db, NullLogger<DashboardController>.Instance);
        var user = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, caregiverId)
        }, "TestAuth"));

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = user }
        };

        return controller;
    }

    [Fact]
    public async Task Fact_43_GetElderDashboard_Resolves_LastKnownGpsLocation()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var dto = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.NotNull(dto.LastKnownGpsLocation);
        Assert.Contains("10.762622", dto.LastKnownGpsLocation);
        Assert.Contains("106.660172", dto.LastKnownGpsLocation);
    }

    [Fact]
    public async Task DemoVitals_AppearOnlyInDemoFields_AndDoNotReplaceRealReadings()
    {
        var measuredAt = DateTime.UtcNow.AddMinutes(-15);
        _db.HealthMeasurements.AddRange(
            new HealthMeasurement
            {
                ElderProfileId = _testElderId, DeviceId = "DEV_01", PacketId = "DEMO_HR",
                MetricType = "DEMO_HEART_RATE", Value = 145, Unit = "bpm",
                Timestamp = measuredAt, RecordedAt = DateTime.UtcNow
            },
            new HealthMeasurement
            {
                ElderProfileId = _testElderId, DeviceId = "DEV_01", PacketId = "DEMO_SPO2",
                MetricType = "DEMO_SPO2", Value = 90, Unit = "%",
                Timestamp = measuredAt, RecordedAt = DateTime.UtcNow
            });
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = Assert.IsType<OkObjectResult>(
            await controller.GetElderDashboard(_testElderId, CancellationToken.None));
        var dashboard = Assert.IsType<ElderDashboardResponse>(result.Value);
        Assert.Equal(65, dashboard.LatestHeartRate?.Value);
        Assert.Equal(98, dashboard.LatestSpO2?.Value);
        Assert.Equal(145, dashboard.DemoHeartRate?.Value);
        Assert.Equal(90, dashboard.DemoSpO2?.Value);

        var chartResult = Assert.IsType<OkObjectResult>(
            await controller.GetElderHeartRate24h(_testElderId, CancellationToken.None));
        var chart = Assert.IsType<HeartRate24hResponse>(chartResult.Value);
        Assert.DoesNotContain(chart.Points, point => point.Value == 145);
    }

    [Fact]
    public async Task Fact_44_GetElderHeartRate24h_Returns_Series_And_Min_Max_Avg()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderHeartRate24h(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<HeartRate24hResponse>(okResult.Value);
        Assert.Equal(3, response.Points.Count);
        Assert.Equal(65, response.MinHeartRate);
        Assert.Equal(88, response.MaxHeartRate);
        Assert.Equal(65, response.LatestHeartRate);
        Assert.True(response.AvgHeartRate > 0);
    }

    [Fact]
    public async Task VitalsCharts_WithoutMeasurements_DoNotInventHealthKitSamples()
    {
        _db.HealthMeasurements.RemoveRange(_db.HealthMeasurements
            .Where(m => m.MetricType == "HEART_RATE" || m.MetricType == "SPO2"));
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var heartRateResult = Assert.IsType<OkObjectResult>(
            await controller.GetElderHeartRate24h(_testElderId, CancellationToken.None));
        var oxygenResult = Assert.IsType<OkObjectResult>(
            await controller.GetElderSpo224h(_testElderId, CancellationToken.None));

        Assert.Empty(Assert.IsType<HeartRate24hResponse>(heartRateResult.Value).Points);
        Assert.Empty(Assert.IsType<Spo224hResponse>(oxygenResult.Value).Points);
    }

    [Fact]
    public async Task Fact_45_GetElderHeartRate24h_Rejects_Unauthorized_Caregiver_BOLA()
    {
        // Arrange
        var controller = CreateController(_unauthCaregiverId);

        // Act
        var result = await controller.GetElderHeartRate24h(_testElderId, CancellationToken.None);

        // Assert
        var objResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, objResult.StatusCode);
    }

    [Fact]
    public async Task Fact_52_GetElderBloodPressureHistory_Returns_Points_And_Classification()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderBloodPressureHistory(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<BloodPressureHistoryResponse>(okResult.Value);
        Assert.NotEmpty(response.Points);
        Assert.Equal(135, response.LatestSystolic);
        Assert.Equal(85, response.LatestDiastolic);
        Assert.Equal("Tiền tăng huyết áp", response.Classification);
        Assert.Equal("YELLOW", response.StatusColor);
    }

    [Fact]
    public async Task Fact_53_GetElderBloodPressureHistory_Enforces_BOLA()
    {
        // Arrange
        var controller = CreateController(_unauthCaregiverId);

        // Act
        var result = await controller.GetElderBloodPressureHistory(_testElderId, CancellationToken.None);

        // Assert
        var objResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, objResult.StatusCode);
    }

    [Fact]
    public async Task Fact_54_GetElderSpo224h_Calculates_Metrics_And_Dips_Below_95()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderSpo224h(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<Spo224hResponse>(okResult.Value);
        Assert.Equal(2, response.Points.Count);
        Assert.Equal(94, response.MinSpo2);
        Assert.Equal(98, response.MaxSpo2);
        Assert.Equal(98, response.LatestSpo2);
        Assert.Equal(1, response.DipsBelow95Count);
        Assert.Equal("GREEN", response.StatusColor);
    }

    [Fact]
    public async Task Fact_55_GetElderHourlySteps24h_Calculates_Distribution_And_Peak()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderHourlySteps24h(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<HourlySteps24hResponse>(okResult.Value);
        Assert.Equal(24, response.HourlySteps.Count);
        Assert.True(response.TotalStepsToday >= 500);
        Assert.Equal(DateTime.UtcNow.Hour, response.PeakHour);
        Assert.Equal(500, response.PeakSteps);
    }

    [Fact]
    public async Task Fact_58_GetElderSleepSummary_ReturnsAccurateDurationAndClinicalQuality()
    {
        // Arrange
        var controller = CreateController(_authCaregiverId);

        // Act
        var result = await controller.GetElderSleepSummary(_testElderId, CancellationToken.None);

        // Assert
        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<SleepSummaryResponse>(okResult.Value);
        Assert.Equal(_testElderId, response.ElderProfileId);
        Assert.True(response.TotalSleepMinutes > 0);
        Assert.True(response.DeepSleepMinutes > 0);
        Assert.True(response.LightSleepMinutes > 0);
        Assert.NotNull(response.SleepQuality);
        Assert.NotNull(response.StatusColor);
    }

    [Fact]
    public async Task Fact_59_GetElderSleepSummary_Rejects_Unauthorized_Caregiver_BOLA()
    {
        // Arrange
        var controller = CreateController(_unauthCaregiverId);

        // Act
        var result = await controller.GetElderSleepSummary(_testElderId, CancellationToken.None);

        // Assert
        var objResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(StatusCodes.Status403Forbidden, objResult.StatusCode);
    }

    [Fact]
    public async Task Fact_52B_GetElderBloodPressureHistory_ReturnsEmpty_WhenNoMeasurements()
    {
        _db.HealthMeasurements.RemoveRange(_db.HealthMeasurements
            .Where(m => m.MetricType.StartsWith("BLOOD_PRESSURE")));
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderBloodPressureHistory(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<BloodPressureHistoryResponse>(okResult.Value);
        Assert.Empty(response.Points);
        Assert.Equal(0, response.LatestSystolic);
        Assert.Equal(0, response.LatestDiastolic);
        Assert.Equal("Chưa có dữ liệu", response.Classification);
        Assert.Equal("GRAY", response.StatusColor);
    }

    [Fact]
    public async Task Fact_60_GetElderSleepSummary_ReturnsZeroAndGray_WhenNoData()
    {
        _db.HealthMeasurements.RemoveRange(_db.HealthMeasurements
            .Where(m => m.MetricType == "SLEEP" || m.MetricType == "SLEEP_STAGE"));
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderSleepSummary(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<SleepSummaryResponse>(okResult.Value);
        Assert.Equal(0, response.TotalSleepMinutes);
        Assert.Null(response.SleepStartTime);
        Assert.Null(response.SleepEndTime);
        Assert.Equal("Chưa có dữ liệu", response.SleepQuality);
        Assert.Equal("GRAY", response.StatusColor);
    }

    [Fact]
    public async Task Fact_WatchStatus_ReturnsNotPaired_WhenNoWatch()
    {
        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.Null(response.WatchModel);
        Assert.Equal("NOT_PAIRED", response.WatchStatus);
    }

    [Fact]
    public async Task Fact_WatchStatus_ReturnsOnline_WhenWatchActiveWithinStaleWindow()
    {
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "WATCH_ACTIVE_01",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "hash123",
            DeviceType = "Smartwatch",
            DeviceModel = "Galaxy Watch6",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow.AddMinutes(-2), // 2 phút < 5 phút Stale
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.Equal("Galaxy Watch6", response.WatchModel);
        Assert.Equal("ONLINE", response.WatchStatus);
    }

    [Fact]
    public async Task Fact_WatchStatus_ReturnsDisconnected_WhenWatchHeartbeatExceedsStaleWindow()
    {
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "WATCH_STALE_01",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "hash123",
            DeviceType = "Smartwatch",
            DeviceModel = "Apple Watch Ultra",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow.AddHours(-4), // 4 giờ > StaleWindow
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.Equal("Apple Watch Ultra", response.WatchModel);
        Assert.Equal("DISCONNECTED", response.WatchStatus);
        Assert.Equal("SIGNAL_LOST", response.WatchDisconnectReason);
    }

    [Fact]
    public async Task Fact_WatchStatus_ReturnsDisconnected_WithBluetoothOffReason()
    {
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "WATCH_BTOFF_01",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "hash123",
            DeviceType = "Smartwatch",
            DeviceModel = "Galaxy Watch6",
            DisconnectReason = "BLUETOOTH_OFF",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow.AddHours(-1),
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.Equal("Galaxy Watch6", response.WatchModel);
        Assert.Equal("DISCONNECTED", response.WatchStatus);
        Assert.Equal("BLUETOOTH_OFF", response.WatchDisconnectReason);
    }

    [Fact]
    public async Task Fact_WatchStatus_ReturnsOnline_ClearsDisconnectReason()
    {
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = "WATCH_ONLINE_RECONNECTED_01",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "hash123",
            DeviceType = "Smartwatch",
            DeviceModel = "Galaxy Watch6",
            DisconnectReason = "BLUETOOTH_OFF", // Trước đó từng có reason nhưng giờ đã kết nối lại
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow.AddMinutes(-1), // Vẫn còn sống trong StaleWindow
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);
        var result = await controller.GetElderDashboard(_testElderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var response = Assert.IsType<ElderDashboardResponse>(okResult.Value);
        Assert.Equal("Galaxy Watch6", response.WatchModel);
        Assert.Equal("ONLINE", response.WatchStatus);
        Assert.Null(response.WatchDisconnectReason);
    }

    [Fact]
    public async Task Fact_WatchTelemetry_SyncsWornChargingAndBattery_ReturnsInDashboard()
    {
        var companionId = "DEV_COMPANION_TEST_01";
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = companionId,
            ElderProfileId = _testElderId,
            DeviceTokenHash = "companion_hash",
            DeviceType = "CompanionPhone",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow,
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
        devicesController.HttpContext.Items["ValidatedDeviceId"] = companionId;

        // Bắn gói tin đồng bộ viễn trắc đồng hồ: Đang đeo, không sạc, pin 88%
        var syncResult = await devicesController.SyncWatch(
            new SyncWatchRequest("Galaxy Watch6", IsConnected: true, DisconnectReason: null, IsWorn: true, IsCharging: false, BatteryLevel: 88),
            CancellationToken.None);

        var okSync = Assert.IsType<OkObjectResult>(syncResult);
        Assert.NotNull(okSync.Value);

        // Truy vấn Dashboard của người thân để kiểm tra dữ liệu viễn trắc đã được cập nhật
        var dashboardController = CreateController(_authCaregiverId);
        var dashResult = await dashboardController.GetElderDashboard(_testElderId, CancellationToken.None);

        var okDash = Assert.IsType<OkObjectResult>(dashResult);
        var response = Assert.IsType<ElderDashboardResponse>(okDash.Value);

        Assert.Equal("Galaxy Watch6", response.WatchModel);
        Assert.Equal("ONLINE", response.WatchStatus);
        Assert.True(response.IsWatchWorn);
        Assert.False(response.IsWatchCharging);
        Assert.Equal(88, response.WatchBatteryLevel);
    }

    [Fact]
    public async Task Fact_WatchTelemetry_UnwornAndCharging_ReturnsCorrectValues()
    {
        var companionId = "DEV_COMPANION_TEST_02";
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = companionId,
            ElderProfileId = _testElderId,
            DeviceTokenHash = "companion_hash_2",
            DeviceType = "CompanionPhone",
            IsActive = true,
            LastHeartbeat = DateTime.UtcNow,
            RegisteredAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
        devicesController.HttpContext.Items["ValidatedDeviceId"] = companionId;

        // Báo trạng thái cắm sạc trên bàn (tháo khỏi cổ tay, đang sạc 100%)
        await devicesController.SyncWatch(
            new SyncWatchRequest("Apple Watch Series 9", IsConnected: true, DisconnectReason: null, IsWorn: false, IsCharging: true, BatteryLevel: 100),
            CancellationToken.None);

        var dashboardController = CreateController(_authCaregiverId);
        var dashResult = await dashboardController.GetElderDashboard(_testElderId, CancellationToken.None);

        var okDash = Assert.IsType<OkObjectResult>(dashResult);
        var response = Assert.IsType<ElderDashboardResponse>(okDash.Value);

        Assert.Equal("Apple Watch Series 9", response.WatchModel);
        Assert.Equal("ONLINE", response.WatchStatus);
        Assert.False(response.IsWatchWorn);
        Assert.True(response.IsWatchCharging);
        Assert.Equal(100, response.WatchBatteryLevel);
    }

    [Fact]
    public async Task Fact_Dashboard_MultipleWatchDevices_PrioritizesFreshestAndDeactivatesZombie()
    {
        var now = DateTime.UtcNow;

        // 1. Giả lập Cụ có 1 bản ghi đồng hồ cũ từ hôm qua (zombie record)
        var staleWatch = new DeviceRegistration
        {
            Id = "WATCH_STALE_YESTERDAY",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "stale_hash",
            DeviceType = "AppleWatch",
            DeviceModel = null,
            IsActive = true,
            LastHeartbeat = now.AddHours(-22),
            RegisteredAt = now.AddHours(-24)
        };

        // 2. Đồng hồ mới thật vừa kết nối hôm nay
        var freshWatch = new DeviceRegistration
        {
            Id = "WATCH_FRESH_TODAY",
            ElderProfileId = _testElderId,
            DeviceTokenHash = "fresh_hash",
            DeviceType = "AppleWatch",
            DeviceModel = "Apple Watch Series 9",
            IsActive = true,
            LastHeartbeat = now.AddSeconds(-10),
            RegisteredAt = now.AddHours(-1)
        };

        _db.DeviceRegistrations.AddRange(staleWatch, freshWatch);
        await _db.SaveChangesAsync();

        // 3. Dashboard phải luôn chọn thiết bị mới nhất (ONLINE) thay vì bị kẹt ở thiết bị cũ (DISCONNECTED / SIGNAL_LOST)
        var dashboardController = CreateController(_authCaregiverId);
        var dashResult = await dashboardController.GetElderDashboard(_testElderId, CancellationToken.None);

        var okDash = Assert.IsType<OkObjectResult>(dashResult);
        var response = Assert.IsType<ElderDashboardResponse>(okDash.Value);

        Assert.Equal("ONLINE", response.WatchStatus);
        Assert.Equal("Apple Watch Series 9", response.WatchModel);

        // 4. Khi SyncWatch được gọi qua trạm Companion, hệ thống tự động vô hiệu hóa bản ghi zombie cũ
        var companionId = "DEV_COMPANION_SYNC_01";
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = companionId,
            ElderProfileId = _testElderId,
            DeviceTokenHash = "comp_hash_01",
            DeviceType = "CompanionPhone",
            IsActive = true,
            LastHeartbeat = now
        });
        await _db.SaveChangesAsync();

        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
        devicesController.HttpContext.Items["ValidatedDeviceId"] = companionId;

        await devicesController.SyncWatch(
            new SyncWatchRequest("Apple Watch Series 9", IsConnected: true, DisconnectReason: null, IsWorn: true, IsCharging: false, BatteryLevel: 95),
            CancellationToken.None);

        var staleFromDb = await _db.DeviceRegistrations.FirstOrDefaultAsync(d => d.Id == "WATCH_STALE_YESTERDAY");
        Assert.NotNull(staleFromDb);
        Assert.False(staleFromDb.IsActive, "Bản ghi đồng hồ cũ (zombie) phải được tự động chuyển sang IsActive = false");
    }

    [Fact]
    public async Task GetActiveIncidentForDevice_ClosedLoopFlow_TracksOpenAcknowledgedAndResolved()
    {
        // 1. Setup companion device for test elder
        var deviceId = "COMPANION_TEST_DEVICE_CLOSED_LOOP";
        _db.DeviceRegistrations.Add(new DeviceRegistration
        {
            Id = deviceId,
            ElderProfileId = _testElderId,
            DeviceType = "Smartphone",
            DeviceTokenHash = "HASH123",
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var devicesController = new DevicesController(_db, NullLogger<DevicesController>.Instance)
        {
            ControllerContext = new ControllerContext
            {
                HttpContext = new DefaultHttpContext()
            }
        };
        devicesController.HttpContext.Items["ValidatedDeviceId"] = deviceId;

        // Ban đầu chưa có sự cố nào
        var initialRes = await devicesController.GetActiveIncidentForDevice(CancellationToken.None);
        var okInitial = Assert.IsType<OkObjectResult>(initialRes);
        var initialDto = Assert.IsType<DeviceActiveIncidentResponse>(okInitial.Value);
        Assert.False(initialDto.HasActiveIncident);
        Assert.Equal("NONE", initialDto.Status);

        // 2. Kích hoạt sự cố SOS (Open)
        var incident = new Incident
        {
            Id = "INC_TEST_CLOSED_LOOP_01",
            ElderProfileId = _testElderId,
            Status = IncidentStatus.Open,
            Severity = IncidentSeverity.Critical,
            EmergencyType = "MANUAL_SOS",
            TriggeredAt = DateTime.UtcNow
        };
        _db.Incidents.Add(incident);
        await _db.SaveChangesAsync();

        var openRes = await devicesController.GetActiveIncidentForDevice(CancellationToken.None);
        var okOpen = Assert.IsType<OkObjectResult>(openRes);
        var openDto = Assert.IsType<DeviceActiveIncidentResponse>(okOpen.Value);
        Assert.True(openDto.HasActiveIncident);
        Assert.Equal("OPEN", openDto.Status);
        Assert.Equal("INC_TEST_CLOSED_LOOP_01", openDto.IncidentId);
        Assert.Null(openDto.AcknowledgedByName);

        // Kiểm tra cả Heartbeat cũng trả về activeIncident
        var hbRes = await devicesController.Heartbeat(new HeartbeatRequest(null, null), CancellationToken.None);
        var okHb = Assert.IsType<OkObjectResult>(hbRes);
        Assert.NotNull(okHb.Value);

        // 3. Người thân tiếp nhận sự cố (Acknowledged)
        incident.Status = IncidentStatus.Acknowledged;
        incident.AcknowledgedAt = DateTime.UtcNow;
        incident.AcknowledgedByCaregiverId = _authCaregiverId;
        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id,
            ActorCaregiverId = _authCaregiverId,
            EventType = "ACKNOWLEDGED",
            Description = "Người thân Nguyễn Văn A đã tiếp nhận sự cố: Đang về hỗ trợ",
            RecordedAt = DateTime.UtcNow
        });
        await _db.SaveChangesAsync();

        var ackRes = await devicesController.GetActiveIncidentForDevice(CancellationToken.None);
        var okAck = Assert.IsType<OkObjectResult>(ackRes);
        var ackDto = Assert.IsType<DeviceActiveIncidentResponse>(okAck.Value);
        Assert.True(ackDto.HasActiveIncident);
        Assert.Equal("ACKNOWLEDGED", ackDto.Status);
        Assert.NotNull(ackDto.AcknowledgedByName);
        Assert.NotNull(ackDto.AcknowledgedNote);

        // 4. Người thân đóng sự cố (Resolved)
        incident.Status = IncidentStatus.Resolved;
        incident.ResolvedAt = DateTime.UtcNow;
        incident.ResolvedByCaregiverId = _authCaregiverId;
        incident.ResolutionNotes = "Đã kiểm tra an toàn";
        await _db.SaveChangesAsync();

        var resolvedRes = await devicesController.GetActiveIncidentForDevice(CancellationToken.None);
        var okResolved = Assert.IsType<OkObjectResult>(resolvedRes);
        var resolvedDto = Assert.IsType<DeviceActiveIncidentResponse>(okResolved.Value);
        Assert.False(resolvedDto.HasActiveIncident);
        Assert.Equal("RESOLVED", resolvedDto.Status);
        Assert.Equal("Đã kiểm tra an toàn", resolvedDto.ResolutionNotes);
    }

    public void Dispose()
    {
        _db.Dispose();
    }
}
