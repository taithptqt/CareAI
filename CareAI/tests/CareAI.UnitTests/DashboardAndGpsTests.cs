using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
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

    public void Dispose()
    {
        _db.Dispose();
    }
}
