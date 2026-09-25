using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Controllers;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using CareAI.Infrastructure.Services;
using Xunit;

namespace CareAI.UnitTests;

public class AdaptiveThresholdTests
{
    private CareAiDbContext CreateInMemoryDb(string dbName)
    {
        var options = new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(databaseName: dbName)
            .Options;
        return new CareAiDbContext(options);
    }

    private IMemoryCache CreateMemoryCache()
    {
        return new MemoryCache(new MemoryCacheOptions
        {
            SizeLimit = 10_000
        });
    }

    // ============================================================================
    // FACT 46: BÁCH PHÂN VỊ P5 VÀ P95 ĐƯỢC TÍNH TOÁN CHUẨN XÁC
    // ============================================================================
    [Fact]
    public void Fact_46_ComputeAdaptiveThresholds_CalculatesP5AndP95_Accurately()
    {
        using var db = CreateInMemoryDb(nameof(Fact_46_ComputeAdaptiveThresholds_CalculatesP5AndP95_Accurately));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);

        // Tạo 100 mẫu nhịp tim phân bố từ 60 đến 100 bpm
        var samples = Enumerable.Range(60, 41)
            .SelectMany(bpm => Enumerable.Repeat((double)bpm, 3)) // 123 mẫu
            .ToList();

        var result = service.ComputeAdaptiveThresholds(
            elderProfileId: "ELDER_TEST_01",
            currentMin: 60.0,
            currentMax: 100.0,
            samples: samples);

        Assert.True(result.HasSufficientData);
        Assert.Equal(123, result.TotalSamplesAnalyzed);
        Assert.True(result.CalculatedP5 >= 60.0 && result.CalculatedP5 <= 65.0, $"CalculatedP5: {result.CalculatedP5}");
        Assert.True(result.CalculatedP95 >= 95.0 && result.CalculatedP95 <= 100.0, $"CalculatedP95: {result.CalculatedP95}");
    }

    // ============================================================================
    // FACT 47: KẸP BIÊN ĐỘ DỊCH CHUYỂN TỐI ĐA 3 BPM/TUẦN (MAX DRIFT CLAMPING)
    // ============================================================================
    [Fact]
    public void Fact_47_ComputeAdaptiveThresholds_ClampsMaxDriftTo3BpmPerWeek()
    {
        using var db = CreateInMemoryDb(nameof(Fact_47_ComputeAdaptiveThresholds_ClampsMaxDriftTo3BpmPerWeek));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);

        // Ngưỡng hiện tại của Cụ: 60 - 100 bpm
        // Giả sử tuần này Cụ luyện tập thể dục, nhịp tim tụt mạnh xuống 45-65 bpm (P5 = 46, P95 = 64)
        // Biên độ biến thiên thực tế rất lớn, nhưng thuật toán BẮT BUỘC chỉ cho phép dịch chuyển tối đa 3 bpm
        var heavyDriftSamples = Enumerable.Repeat(46.0, 10)
            .Concat(Enumerable.Repeat(55.0, 30))
            .Concat(Enumerable.Repeat(64.0, 10))
            .ToList(); // 50 mẫu

        var result = service.ComputeAdaptiveThresholds(
            elderProfileId: "ELDER_DRIFT_01",
            currentMin: 60.0,
            currentMax: 100.0,
            samples: heavyDriftSamples);

        Assert.True(result.HasSufficientData);
        // Min cũ 60 -> P5 = 46 -> Drift clamp xuống tối đa 60 - 3 = 57 bpm
        Assert.Equal(57.0, result.RecommendedMinBpm);
        // Max cũ 100 -> P95 = 64 -> Drift clamp xuống tối đa 100 - 3 = 97 bpm
        Assert.Equal(97.0, result.RecommendedMaxBpm);
    }

    // ============================================================================
    // FACT 48: BẢO VỆ CẬN LÂM SÀNG TUYỆT ĐỐI (RECOMMENDED_MIN >= 40, RECOMMENDED_MAX <= 160)
    // ============================================================================
    [Fact]
    public void Fact_48_ComputeAdaptiveThresholds_EnforcesClinicalAbsoluteBounds()
    {
        using var db = CreateInMemoryDb(nameof(Fact_48_ComputeAdaptiveThresholds_EnforcesClinicalAbsoluteBounds));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);

        // Dữ liệu nhịp tim tụt cực thấp hoặc cực cao
        var extremeLowSamples = Enumerable.Repeat(32.0, 30).ToList();
        var resultLow = service.ComputeAdaptiveThresholds(
            elderProfileId: "ELDER_EXTREME_LOW",
            currentMin: 42.0,
            currentMax: 100.0,
            samples: extremeLowSamples);

        // Dù P5 = 32 bpm, cận an toàn lâm sàng tuyệt đối chặn ở >= 40 bpm
        Assert.True(resultLow.RecommendedMinBpm >= 40.0, $"RecommendedMin should be >= 40, was: {resultLow.RecommendedMinBpm}");

        var extremeHighSamples = Enumerable.Repeat(175.0, 30).ToList();
        var resultHigh = service.ComputeAdaptiveThresholds(
            elderProfileId: "ELDER_EXTREME_HIGH",
            currentMin: 60.0,
            currentMax: 158.0,
            samples: extremeHighSamples);

        // Dù P95 = 175 bpm, cận an toàn lâm sàng tuyệt đối chặn ở <= 160 bpm
        Assert.True(resultHigh.RecommendedMaxBpm <= 160.0, $"RecommendedMax should be <= 160, was: {resultHigh.RecommendedMaxBpm}");
    }

    // ============================================================================
    // FACT 49: CẬP NHẬT CSDL & LÀM MỚI TỨC THÌ BỘ NHỚ ĐỆM (ZERO-DOWNTIME CACHE INVALIDATION)
    // ============================================================================
    [Fact]
    public async Task Fact_49_UpdateThresholds_UpdatesDb_AndInvalidatesMemoryCache_Instantly()
    {
        using var db = CreateInMemoryDb(nameof(Fact_49_UpdateThresholds_UpdatesDb_AndInvalidatesMemoryCache_Instantly));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);

        var elder = new ElderProfile
        {
            Id = "ELDER_CACHE_TEST",
            FullName = "Cụ Bà Nguyễn Thị Mai",
            DateOfBirth = new DateTime(1945, 5, 20),
            RestingHeartRateMin = 40.0,
            RestingHeartRateMax = 120.0
        };
        db.ElderProfiles.Add(elder);
        await db.SaveChangesAsync();

        // 1. Lần đầu đọc: Nạp vào IMemoryCache
        var initialThresholds = await service.GetEffectiveThresholdsAsync(elder.Id);
        Assert.Equal(40.0, initialThresholds.Min);
        Assert.Equal(120.0, initialThresholds.Max);

        // 2. Cập nhật ngưỡng thích nghi mới qua UpdateThresholdsAsync
        var updated = await service.UpdateThresholdsAsync(elder.Id, minBpm: 52.0, maxBpm: 112.0);
        Assert.Equal(52.0, updated.RestingHeartRateMin);
        Assert.Equal(112.0, updated.RestingHeartRateMax);

        // 3. Đọc lại ngay lập tức từ GetEffectiveThresholdsAsync (Zero-Downtime Cache Invalidation)
        var cachedThresholds = await service.GetEffectiveThresholdsAsync(elder.Id);
        Assert.Equal(52.0, cachedThresholds.Min);
        Assert.Equal(112.0, cachedThresholds.Max);

        // 4. Kiểm tra CSDL cũng đã được lưu bền vững
        var dbElder = await db.ElderProfiles.AsNoTracking().FirstOrDefaultAsync(e => e.Id == elder.Id);
        Assert.NotNull(dbElder);
        Assert.Equal(52.0, dbElder.RestingHeartRateMin);
        Assert.Equal(112.0, dbElder.RestingHeartRateMax);
        Assert.NotNull(dbElder.ThresholdsUpdatedAt);
    }

    // ============================================================================
    // FACT 50: BẢO VỆ PHÂN QUYỀN BOLA TRÊN ENDPOINT QUẢN LÝ NGƯỠNG
    // ============================================================================
    [Fact]
    public async Task Fact_50_EldersController_EnforcesBola_OnThresholdManagement()
    {
        using var db = CreateInMemoryDb(nameof(Fact_50_EldersController_EnforcesBola_OnThresholdManagement));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);
        var controller = new EldersController(db, service, NullLogger<EldersController>.Instance);

        var elder = new ElderProfile
        {
            Id = "ELDER_BOLA_TEST",
            FullName = "Cụ Ông Trần Văn Ba",
            DateOfBirth = new DateTime(1940, 1, 1),
            RestingHeartRateMin = 45.0,
            RestingHeartRateMax = 115.0
        };
        db.ElderProfiles.Add(elder);

        var authorizedCaregiver = new Caregiver
        {
            Id = "CAREGIVER_AUTH",
            FullName = "Người thân chính thức",
            PhoneNumber = "0901111222",
            Email = "auth@careai.vn"
        };
        db.Caregivers.Add(authorizedCaregiver);

        db.ElderCaregivers.Add(new ElderCaregiver
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = elder.Id,
            CaregiverId = authorizedCaregiver.Id,
            IsActive = true
        });
        await db.SaveChangesAsync();

        // Giả lập Người thân KHÔNG được phân quyền chăm sóc (Attacker / Unauthorized Caregiver)
        var unauthorizedUser = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, "CAREGIVER_STRANGER")
        }, "mock"));

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = unauthorizedUser }
        };

        // Thử cập nhật ngưỡng
        var updateResult = await controller.UpdateThresholds(elder.Id, new UpdateThresholdsRequest(50.0, 110.0), CancellationToken.None);
        var forbiddenResult = Assert.IsType<ObjectResult>(updateResult);
        Assert.Equal(StatusCodes.Status403Forbidden, forbiddenResult.StatusCode);

        // Chuyển sang Người thân HỢP LỆ
        var authorizedUser = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, authorizedCaregiver.Id)
        }, "mock"));

        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext { User = authorizedUser }
        };

        var validResult = await controller.UpdateThresholds(elder.Id, new UpdateThresholdsRequest(50.0, 110.0), CancellationToken.None);
        var okResult = Assert.IsType<OkObjectResult>(validResult);
        var thresholdResp = Assert.IsType<ThresholdResponse>(okResult.Value);
        Assert.Equal(50.0, thresholdResp.RestingHeartRateMin);
        Assert.Equal(110.0, thresholdResp.RestingHeartRateMax);
    }

    // ============================================================================
    // FACT 51: CLINICAL DIAGNOSTIC ENGINE SỬ DỤNG NGƯỠNG THÍCH NGHI CÁ NHÂN HÓA
    // ============================================================================
    [Fact]
    public async Task Fact_51_ClinicalDiagnosticEngine_UsesPersonalizedAdaptiveThresholds()
    {
        using var db = CreateInMemoryDb(nameof(Fact_51_ClinicalDiagnosticEngine_UsesPersonalizedAdaptiveThresholds));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);
        var engine = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance, service);

        var elder = new ElderProfile
        {
            Id = "ELDER_ADAPTIVE_ENGINE",
            FullName = "Cụ Lê Văn Tám",
            DateOfBirth = new DateTime(1938, 8, 15),
            RestingHeartRateMin = 55.0, // Ngưỡng tối thiểu được điều chỉnh lên 55 bpm
            RestingHeartRateMax = 105.0 // Ngưỡng tối đa được điều chỉnh xuống 105 bpm
        };
        db.ElderProfiles.Add(elder);
        await db.SaveChangesAsync();

        // 1. Nhịp tim 108 bpm khi ngồi nghỉ (steps = 0):
        // Mặc định chuẩn chung là 120 bpm thì không báo, nhưng với Cụ Tám đã thích nghi ngưỡng 105 bpm -> Báo Tachycardia!
        var incidentHigh = await engine.EvaluateHeartRateSampleAsync(
            elderProfileId: elder.Id,
            deviceId: "DEV_TEST",
            heartRate: 108.0,
            recentSteps: 0);

        Assert.NotNull(incidentHigh);
        Assert.Equal(EmergencyType.Tachycardia, incidentHigh.EmergencyType);
        Assert.Equal(IncidentSeverity.High, incidentHigh.Severity);

        // 2. Nhịp tim nguy kịch tuyệt đối (>= 180 bpm): Bất biến cứu sinh luôn giữ Critical
        var incidentCrit = await engine.EvaluateHeartRateSampleAsync(
            elderProfileId: "ELDER_CRIT",
            deviceId: "DEV_TEST",
            heartRate: 185.0,
            recentSteps: 0);

        Assert.NotNull(incidentCrit);
        Assert.Equal(IncidentSeverity.Critical, incidentCrit.Severity);
    }

    // ============================================================================
    // FACT 56: BỘ CHUYỂN ĐỔI NGƯỠNG THÍCH NGHI NGÀY/ĐÊM (CIRCADIAN SLEEP WINDOW)
    // ============================================================================
    [Fact]
    public async Task Fact_56_CircadianSleepWindow_SwitchesThresholdsDynamically()
    {
        using var db = CreateInMemoryDb(nameof(Fact_56_CircadianSleepWindow_SwitchesThresholdsDynamically));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);

        var elder = new ElderProfile
        {
            Id = "ELDER_CIRCADIAN_01",
            FullName = "Cụ Hoàng Thị Mai",
            DateOfBirth = new DateTime(1942, 5, 20),
            RestingHeartRateMin = 50.0,
            RestingHeartRateMax = 115.0,
            NightHeartRateMin = 42.0,
            NightHeartRateMax = 88.0,
            SleepWindowStart = "22:00",
            SleepWindowEnd = "06:00"
        };
        db.ElderProfiles.Add(elder);
        await db.SaveChangesAsync();

        // 1. Kiểm tra thời điểm ban ngày (14:30) -> Dùng ngưỡng ban ngày
        var dayTime = new DateTime(2026, 9, 25, 14, 30, 0, DateTimeKind.Utc);
        var dayThresholds = await service.GetEffectiveThresholdsForTimeAsync(elder.Id, dayTime);
        Assert.False(dayThresholds.IsNight);
        Assert.Equal(50.0, dayThresholds.Min);
        Assert.Equal(115.0, dayThresholds.Max);

        // 2. Kiểm tra thời điểm ban đêm (02:15) -> Dùng ngưỡng ban đêm
        var nightTime = new DateTime(2026, 9, 25, 2, 15, 0, DateTimeKind.Utc);
        var nightThresholds = await service.GetEffectiveThresholdsForTimeAsync(elder.Id, nightTime);
        Assert.True(nightThresholds.IsNight);
        Assert.Equal(42.0, nightThresholds.Min);
        Assert.Equal(88.0, nightThresholds.Max);

        // 3. Cập nhật dải ngưỡng ngày/đêm mới và kiểm tra cache làm mới
        var updated = await service.UpdateThresholdsAsync(
            elder.Id,
            minBpm: 52.0,
            maxBpm: 110.0,
            nightMinBpm: 44.0,
            nightMaxBpm: 85.0,
            sleepStart: "21:30",
            sleepEnd: "05:30"
        );
        Assert.Equal(52.0, updated.RestingHeartRateMin);
        Assert.Equal(110.0, updated.RestingHeartRateMax);
        Assert.Equal(44.0, updated.NightHeartRateMin);
        Assert.Equal(85.0, updated.NightHeartRateMax);
        Assert.Equal("21:30", updated.SleepWindowStart);
        Assert.Equal("05:30", updated.SleepWindowEnd);
    }

    // ============================================================================
    // FACT 57: ĐỘNG CƠ LÂM SÀNG PHÂN BIỆT NGÀY/ĐÊM VÀ TRIỆT TIÊU BÁO ĐỘNG GIẢ LÚC NGỦ
    // ============================================================================
    [Fact]
    public async Task Fact_57_ClinicalEngine_DistinguishesDayAndNight_SuppressesSleepFalseAlarms()
    {
        using var db = CreateInMemoryDb(nameof(Fact_57_ClinicalEngine_DistinguishesDayAndNight_SuppressesSleepFalseAlarms));
        using var cache = CreateMemoryCache();
        var service = new AdaptiveThresholdService(db, cache, NullLogger<AdaptiveThresholdService>.Instance);
        var engine = new ClinicalDiagnosticEngine(db, NullLogger<ClinicalDiagnosticEngine>.Instance, service);

        var elder = new ElderProfile
        {
            Id = "ELDER_SLEEP_ENGINE",
            FullName = "Cụ Trần Văn Bình",
            DateOfBirth = new DateTime(1940, 3, 10),
            RestingHeartRateMin = 50.0, // Ban ngày min 50 bpm
            RestingHeartRateMax = 110.0,
            NightHeartRateMin = 40.0,   // Ban đêm cho phép chậm tới 40 bpm
            NightHeartRateMax = 90.0,    // Ban đêm giới hạn trần 90 bpm
            SleepWindowStart = "00:00",
            SleepWindowEnd = "23:59"    // Cố định toàn khung giờ để mô phỏng trạng thái đêm
        };
        db.ElderProfiles.Add(elder);
        await db.SaveChangesAsync();

        // 1. Nhịp tim 45 bpm trong khung giờ ngủ:
        // Nếu dùng ngưỡng ngày (min 50) sẽ báo nhịp chậm (False Alarm).
        // Khi dùng ngưỡng đêm (min 40), 45 bpm là bình thường sinh lý lúc ngủ -> KHÔNG sinh sự cố!
        var incidentSleepNormal = await engine.EvaluateHeartRateSampleAsync(
            elderProfileId: elder.Id,
            deviceId: "DEV_TEST",
            heartRate: 45.0,
            recentSteps: 0);

        Assert.Null(incidentSleepNormal);

        // 2. Nhịp tim 95 bpm trong khung giờ ngủ:
        // Vượt quá trần ban đêm (NightMax = 90) -> Sinh cảnh báo nhịp nhanh ban đêm (Nocturnal Tachycardia)
        var incidentNightTachycardia = await engine.EvaluateHeartRateSampleAsync(
            elderProfileId: elder.Id,
            deviceId: "DEV_TEST",
            heartRate: 95.0,
            recentSteps: 0);

        Assert.NotNull(incidentNightTachycardia);
        Assert.Equal(EmergencyType.Tachycardia, incidentNightTachycardia.EmergencyType);
        Assert.Contains("ban đêm (lúc ngủ)", incidentNightTachycardia.TimelineEvents.First().Description);
    }
}
