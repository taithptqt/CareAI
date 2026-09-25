using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Interfaces;
using CareAI.Infrastructure.Data;

namespace CareAI.Infrastructure.Services;

public class AdaptiveThresholdService : IAdaptiveThresholdService
{
    private readonly CareAiDbContext _db;
    private readonly IMemoryCache _cache;
    private readonly ILogger<AdaptiveThresholdService> _logger;

    public const double ClinicalAbsoluteMinBpm = 40.0;
    public const double ClinicalAbsoluteMaxBpm = 160.0;
    public const double MaxDriftBpmPerWeek = 3.0;
    public const int MinimumRequiredSamples = 20;

    public AdaptiveThresholdService(
        CareAiDbContext db,
        IMemoryCache cache,
        ILogger<AdaptiveThresholdService> logger)
    {
        _db = db;
        _cache = cache;
        _logger = logger;
    }

    /// <summary>
    /// Tính toán đề xuất dải ngưỡng an toàn thích nghi từ 14 ngày lịch sử đo nhịp tim nghỉ ngơi.
    /// </summary>
    public async Task<ThresholdRecommendationDto> CalculateRecommendationAsync(string elderProfileId, CancellationToken ct = default)
    {
        var elder = await _db.ElderProfiles.AsNoTracking()
            .FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);

        if (elder == null)
        {
            throw new KeyNotFoundException($"Không tìm thấy hồ sơ người cao tuổi với mã {elderProfileId}.");
        }

        var cutoffDate = DateTime.UtcNow.AddDays(-14);

        // Lấy các mẫu đo nhịp tim trong vòng 14 ngày qua
        var heartRateSamples = await _db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == elderProfileId &&
                        m.MetricType == "HEART_RATE" &&
                        m.Timestamp >= cutoffDate &&
                        m.Value >= 30 && m.Value <= 220) // Lọc bỏ giá trị nhiễu cảm biến bất thường
            .Select(m => m.Value)
            .ToListAsync(ct);

        return ComputeAdaptiveThresholds(
            elderProfileId,
            elder.RestingHeartRateMin,
            elder.RestingHeartRateMax,
            heartRateSamples);
    }

    /// <summary>
    /// Hàm thuần túy toán học: Tính toán bách phân vị P5, P95, kẹp giới hạn cận lâm sàng [40, 160] và kẹp biên độ dịch chuyển tối đa 3 bpm/tuần.
    /// </summary>
    public ThresholdRecommendationDto ComputeAdaptiveThresholds(
        string elderProfileId,
        double currentMin,
        double currentMax,
        IReadOnlyList<double> samples)
    {
        var now = DateTime.UtcNow;

        if (samples == null || samples.Count < MinimumRequiredSamples)
        {
            var count = samples?.Count ?? 0;
            return new ThresholdRecommendationDto(
                ElderProfileId: elderProfileId,
                CurrentMinBpm: currentMin,
                CurrentMaxBpm: currentMax,
                CalculatedP5: currentMin,
                CalculatedP95: currentMax,
                RecommendedMinBpm: currentMin,
                RecommendedMaxBpm: currentMax,
                TotalSamplesAnalyzed: count,
                AnalyzedAt: now,
                HasSufficientData: false,
                ClinicalRationale: $"Dữ liệu thu thập chưa đủ 14 ngày (hiện có {count}/{MinimumRequiredSamples} mẫu tối thiểu). Giữ nguyên ngưỡng an toàn lâm sàng hiện tại ({currentMin:F0} - {currentMax:F0} bpm)."
            );
        }

        // 1. Sắp xếp chuỗi đo tăng dần
        var sorted = samples.OrderBy(v => v).ToList();
        var n = sorted.Count;

        // 2. Tính toán bách phân vị (Linear Interpolation Percentile)
        var p5 = CalculatePercentile(sorted, 0.05);
        var p95 = CalculatePercentile(sorted, 0.95);

        // 3. Kẹp giới hạn cận lâm sàng tuyệt đối (Clinical Absolute Clamping)
        // RecommendedMin >= 40 bpm, RecommendedMax <= 160 bpm
        var rawMin = Math.Max(ClinicalAbsoluteMinBpm, p5);
        var rawMax = Math.Min(ClinicalAbsoluteMaxBpm, p95);

        // Đảm bảo khoảng cách sinh lý tối thiểu 15 bpm giữa Min và Max
        if (rawMax - rawMin < 15.0)
        {
            rawMax = Math.Min(ClinicalAbsoluteMaxBpm, rawMin + 15.0);
        }

        // 4. Kẹp biên độ dịch chuyển tối đa 3 bpm/tuần (Max Drift Clamping)
        // Tránh sốc ngưỡng do sự cố sinh lý ngắn hạn gây ra
        var deltaMin = rawMin - currentMin;
        var clampedDeltaMin = Math.Clamp(deltaMin, -MaxDriftBpmPerWeek, MaxDriftBpmPerWeek);
        var recommendedMin = currentMin + clampedDeltaMin;

        var deltaMax = rawMax - currentMax;
        var clampedDeltaMax = Math.Clamp(deltaMax, -MaxDriftBpmPerWeek, MaxDriftBpmPerWeek);
        var recommendedMax = currentMax + clampedDeltaMax;

        // 5. Bảo vệ an toàn lần cuối sau khi dịch chuyển
        recommendedMin = Math.Round(Math.Max(ClinicalAbsoluteMinBpm, recommendedMin), 1);
        recommendedMax = Math.Round(Math.Min(ClinicalAbsoluteMaxBpm, recommendedMax), 1);

        if (recommendedMax - recommendedMin < 15.0)
        {
            recommendedMax = Math.Min(ClinicalAbsoluteMaxBpm, recommendedMin + 15.0);
        }

        var rationale = $"Phân tích {n} mẫu nhịp tim 14 ngày: P5={p5:F1} bpm, P95={p95:F1} bpm. " +
                        $"Giới hạn dịch chuyển an toàn ±{MaxDriftBpmPerWeek:F0} bpm/tuần từ ngưỡng hiện tại [{currentMin:F0}, {currentMax:F0} bpm] " +
                        $"-> Ngưỡng thích nghi cá nhân hóa đề xuất: [{recommendedMin:F0}, {recommendedMax:F0} bpm].";

        return new ThresholdRecommendationDto(
            ElderProfileId: elderProfileId,
            CurrentMinBpm: currentMin,
            CurrentMaxBpm: currentMax,
            CalculatedP5: Math.Round(p5, 1),
            CalculatedP95: Math.Round(p95, 1),
            RecommendedMinBpm: recommendedMin,
            RecommendedMaxBpm: recommendedMax,
            TotalSamplesAnalyzed: n,
            AnalyzedAt: now,
            HasSufficientData: true,
            ClinicalRationale: rationale
        );
    }

    /// <summary>
    /// Cập nhật dải ngưỡng mới vào CSDL và làm mới IMemoryCache ngay lập tức (Zero-Downtime Cache Invalidation).
    /// </summary>
    public async Task<ThresholdResponse> UpdateThresholdsAsync(
        string elderProfileId,
        double minBpm,
        double maxBpm,
        double? nightMinBpm = null,
        double? nightMaxBpm = null,
        string? sleepStart = null,
        string? sleepEnd = null,
        CancellationToken ct = default)
    {
        if (minBpm < ClinicalAbsoluteMinBpm)
        {
            throw new ArgumentException($"Ngưỡng nhịp tim tối thiểu không được nhỏ hơn giới hạn an toàn {ClinicalAbsoluteMinBpm} bpm.");
        }

        if (maxBpm > ClinicalAbsoluteMaxBpm)
        {
            throw new ArgumentException($"Ngưỡng nhịp tim tối đa không được vượt quá giới hạn an toàn {ClinicalAbsoluteMaxBpm} bpm.");
        }

        if (minBpm >= maxBpm)
        {
            throw new ArgumentException("Ngưỡng nhịp tim tối thiểu phải nhỏ hơn ngưỡng tối đa.");
        }

        var elder = await _db.ElderProfiles.FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);
        if (elder == null)
        {
            throw new KeyNotFoundException($"Không tìm thấy hồ sơ người cao tuổi với mã {elderProfileId}.");
        }

        var now = DateTime.UtcNow;
        elder.RestingHeartRateMin = minBpm;
        elder.RestingHeartRateMax = maxBpm;
        if (nightMinBpm.HasValue) elder.NightHeartRateMin = nightMinBpm.Value;
        if (nightMaxBpm.HasValue) elder.NightHeartRateMax = nightMaxBpm.Value;
        if (!string.IsNullOrWhiteSpace(sleepStart)) elder.SleepWindowStart = sleepStart;
        if (!string.IsNullOrWhiteSpace(sleepEnd)) elder.SleepWindowEnd = sleepEnd;
        elder.ThresholdsUpdatedAt = now;
        elder.UpdatedAt = now;

        await _db.SaveChangesAsync(ct);

        // ZERO-DOWNTIME CACHE INVALIDATION & IMMEDIATE RE-PRIMING:
        // Tuân thủ bất biến Sổ tay kinh nghiệm mục 18.1: entry.Size = 1;
        var cacheKey = $"elder_thresholds_{elderProfileId}";
        _cache.Remove(cacheKey);

        _cache.Set(cacheKey, (
            DayMin: elder.RestingHeartRateMin,
            DayMax: elder.RestingHeartRateMax,
            NightMin: elder.NightHeartRateMin,
            NightMax: elder.NightHeartRateMax,
            SleepStart: elder.SleepWindowStart,
            SleepEnd: elder.SleepWindowEnd
        ), new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1),
            Size = 1
        });

        _logger.LogInformation("[ADAPTIVE-THRESHOLDS] Đã cập nhật ngưỡng thích nghi cho Cụ {ElderId}: Ngày=[{DayMin}, {DayMax}] bpm, Đêm=[{NightMin}, {NightMax}] bpm, Giờ ngủ={SleepStart}-{SleepEnd}.",
            elderProfileId, elder.RestingHeartRateMin, elder.RestingHeartRateMax, elder.NightHeartRateMin, elder.NightHeartRateMax, elder.SleepWindowStart, elder.SleepWindowEnd);

        var isCurrentlySleep = IsInSleepWindow(DateTime.UtcNow, elder.SleepWindowStart, elder.SleepWindowEnd);

        return new ThresholdResponse(
            ElderProfileId: elderProfileId,
            RestingHeartRateMin: elder.RestingHeartRateMin,
            RestingHeartRateMax: elder.RestingHeartRateMax,
            UpdatedAt: now,
            NightHeartRateMin: elder.NightHeartRateMin,
            NightHeartRateMax: elder.NightHeartRateMax,
            SleepWindowStart: elder.SleepWindowStart,
            SleepWindowEnd: elder.SleepWindowEnd,
            IsCurrentlySleepWindow: isCurrentlySleep
        );
    }

    private async Task<(double DayMin, double DayMax, double NightMin, double NightMax, string SleepStart, string SleepEnd)> GetThresholdDataInternalAsync(string elderProfileId, CancellationToken ct = default)
    {
        var cacheKey = $"elder_thresholds_{elderProfileId}";

        return await _cache.GetOrCreateAsync(cacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromHours(1);
            entry.Size = 1; // BẮT BUỘC: Sổ tay kinh nghiệm mục 18.1

            var elder = await _db.ElderProfiles.AsNoTracking()
                .FirstOrDefaultAsync(e => e.Id == elderProfileId, ct);

            return (
                DayMin: elder?.RestingHeartRateMin ?? ClinicalAbsoluteMinBpm,
                DayMax: elder?.RestingHeartRateMax ?? 120.0,
                NightMin: elder?.NightHeartRateMin ?? 40.0,
                NightMax: elder?.NightHeartRateMax ?? 90.0,
                SleepStart: elder?.SleepWindowStart ?? "22:00",
                SleepEnd: elder?.SleepWindowEnd ?? "06:00"
            );
        });
    }

    /// <summary>
    /// Lấy dải ngưỡng hiệu lực (ưu tiên IMemoryCache với fallback CSDL).
    /// </summary>
    public async Task<(double Min, double Max)> GetEffectiveThresholdsAsync(string elderProfileId, CancellationToken ct = default)
    {
        var data = await GetThresholdDataInternalAsync(elderProfileId, ct);
        return (data.DayMin, data.DayMax);
    }

    /// <summary>
    /// Lấy dải ngưỡng hiệu lực tương ứng theo thời gian (tự động phân biệt Ngày và Đêm theo Khung giờ ngủ).
    /// </summary>
    public async Task<(double Min, double Max, bool IsNight)> GetEffectiveThresholdsForTimeAsync(string elderProfileId, DateTime timestamp, CancellationToken ct = default)
    {
        var data = await GetThresholdDataInternalAsync(elderProfileId, ct);
        var isNight = IsInSleepWindow(timestamp, data.SleepStart, data.SleepEnd);
        if (isNight)
        {
            return (data.NightMin, data.NightMax, true);
        }
        return (data.DayMin, data.DayMax, false);
    }

    public static bool IsInSleepWindow(DateTime timestamp, string windowStart = "22:00", string windowEnd = "06:00")
    {
        if (!TimeSpan.TryParse(windowStart, out var start)) start = new TimeSpan(22, 0, 0);
        if (!TimeSpan.TryParse(windowEnd, out var end)) end = new TimeSpan(6, 0, 0);

        var time = timestamp.TimeOfDay;
        if (start <= end)
        {
            return time >= start && time < end;
        }
        else
        {
            return time >= start || time < end;
        }
    }

    private static double CalculatePercentile(List<double> sorted, double percentile)
    {
        var n = sorted.Count;
        if (n == 0) return 0;
        if (n == 1) return sorted[0];

        var rank = percentile * (n - 1);
        var lowerIndex = (int)Math.Floor(rank);
        var upperIndex = (int)Math.Ceiling(rank);

        if (lowerIndex == upperIndex)
        {
            return sorted[lowerIndex];
        }

        var fraction = rank - lowerIndex;
        return sorted[lowerIndex] + fraction * (sorted[upperIndex] - sorted[lowerIndex]);
    }
}
