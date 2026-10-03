using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using CareAI.API.Controllers;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Data;
using Xunit;

namespace CareAI.UnitTests;

public class VitalsControllerTests : IDisposable
{
    private readonly CareAiDbContext _db;
    private readonly string _elderId = "ELDER_VITALS_001";
    private readonly string _authCaregiverId = "CAREGIVER_VITALS_01";
    private readonly string _unauthCaregiverId = "CAREGIVER_VITALS_99";

    public VitalsControllerTests()
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: $"CareAiDb_VitalsTest_{Guid.NewGuid()}")
            .Options;

        _db = new CareAiDbContext(options);
        SeedData();
    }

    private void SeedData()
    {
        _db.ElderProfiles.Add(new ElderProfile
        {
            Id = _elderId,
            FullName = "Cụ Nguyễn Văn Hùng",
            DateOfBirth = new DateTime(1948, 1, 1),
            CreatedAt = DateTime.UtcNow
        });

        _db.ElderCaregivers.Add(new ElderCaregiver
        {
            CaregiverId = _authCaregiverId,
            ElderProfileId = _elderId,
            IsActive = true
        });

        var now = DateTime.UtcNow;
        _db.HealthMeasurements.AddRange(
            new HealthMeasurement
            {
                ElderProfileId = _elderId,
                DeviceId = "DEV_WATCH",
                PacketId = "P_V1",
                MetricType = "HEART_RATE",
                Value = 78,
                Unit = "bpm",
                Timestamp = now.AddHours(-1),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _elderId,
                DeviceId = "DEV_WATCH",
                PacketId = "P_V2",
                MetricType = "SPO2",
                Value = 97,
                Unit = "%",
                Timestamp = now.AddHours(-2),
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _elderId,
                DeviceId = "DEV_WATCH",
                PacketId = "P_V3",
                MetricType = "HEART_RATE",
                Value = 70,
                Unit = "bpm",
                Timestamp = now.AddHours(-30), // Quá 24 giờ
                RecordedAt = now
            },
            new HealthMeasurement
            {
                ElderProfileId = _elderId,
                DeviceId = "DEV_WATCH",
                PacketId = "P_V4",
                MetricType = "STEPS",
                Value = 1200,
                Unit = "steps",
                Timestamp = now.AddHours(-1),
                RecordedAt = now
            }
        );

        _db.SaveChanges();
    }

    private VitalsController CreateController(string? caregiverId)
    {
        var controller = new VitalsController(_db);
        var claims = new List<Claim>();
        if (!string.IsNullOrEmpty(caregiverId))
        {
            claims.Add(new Claim(ClaimTypes.NameIdentifier, caregiverId));
        }

        var identity = new ClaimsIdentity(claims, caregiverId != null ? "TestAuth" : null);
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(identity)
            }
        };

        return controller;
    }

    [Fact]
    public async Task GetRecent_ReturnsUnauthorized_WhenCaregiverNotAuthenticated()
    {
        var controller = CreateController(null);

        var result = await controller.GetRecent(_elderId, CancellationToken.None);

        Assert.IsType<UnauthorizedResult>(result);
    }

    [Fact]
    public async Task GetRecent_ReturnsForbid_WhenCaregiverNotAuthorizedForElder_BOLA()
    {
        var controller = CreateController(_unauthCaregiverId);

        var result = await controller.GetRecent(_elderId, CancellationToken.None);

        Assert.IsType<ForbidResult>(result);
    }

    [Fact]
    public async Task GetRecent_ReturnsRecentRawMeasurements_Within24Hours_WhenAuthorized()
    {
        var controller = CreateController(_authCaregiverId);

        var result = await controller.GetRecent(_elderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var items = Assert.IsAssignableFrom<System.Collections.IEnumerable>(okResult.Value);
        var list = items.Cast<object>().ToList();

        // Chỉ chứa 2 mẫu (HEART_RATE và SPO2 trong vòng 24h, loại bỏ mẫu >24h và STEPS)
        Assert.Equal(2, list.Count);
    }

    [Fact]
    public async Task GetRecent_ReturnsEmptyList_WhenNoMeasurementsWithin24Hours()
    {
        _db.HealthMeasurements.RemoveRange(_db.HealthMeasurements
            .Where(m => m.ElderProfileId == _elderId && m.Timestamp >= DateTime.UtcNow.AddHours(-24)));
        await _db.SaveChangesAsync();

        var controller = CreateController(_authCaregiverId);

        var result = await controller.GetRecent(_elderId, CancellationToken.None);

        var okResult = Assert.IsType<OkObjectResult>(result);
        var items = Assert.IsAssignableFrom<System.Collections.IEnumerable>(okResult.Value);
        var list = items.Cast<object>().ToList();

        Assert.Empty(list);
    }

    public void Dispose()
    {
        _db.Dispose();
    }
}
