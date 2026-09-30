using CareAI.Core.DTOs;

namespace CareAI.Core.Interfaces;

public interface IAdaptiveThresholdService
{
    /// <summary>
    /// Tính toán đề xuất dải ngưỡng an toàn thích nghi từ 14 ngày lịch sử đo nhịp tim nghỉ ngơi.
    /// </summary>
    Task<ThresholdRecommendationDto> CalculateRecommendationAsync(string elderProfileId, CancellationToken ct = default);

    /// <summary>
    /// Cập nhật dải ngưỡng mới vào CSDL và làm mới IMemoryCache ngay lập tức (Zero-Downtime Cache Invalidation).
    /// </summary>
    Task<ThresholdResponse> UpdateThresholdsAsync(
        string elderProfileId,
        double minBpm,
        double maxBpm,
        double? nightMinBpm = null,
        double? nightMaxBpm = null,
        string? sleepStart = null,
        string? sleepEnd = null,
        CancellationToken ct = default);

    /// <summary>
    /// Lấy dải ngưỡng hiệu lực (ưu tiên IMemoryCache với fallback CSDL).
    /// </summary>
    Task<(double Min, double Max)> GetEffectiveThresholdsAsync(string elderProfileId, CancellationToken ct = default);

    /// <summary>
    /// Lấy dải ngưỡng hiệu lực tương ứng theo thời gian (tự động phân biệt Ngày và Đêm theo Khung giờ ngủ).
    /// </summary>
    Task<(double Min, double Max, bool IsNight)> GetEffectiveThresholdsForTimeAsync(string elderProfileId, DateTime timestamp, CancellationToken ct = default);

    /// <summary>
    /// Hàm thuần túy toán học: Tính toán bách phân vị P5, P95, kẹp giới hạn cận lâm sàng [40, 160] và kẹp biên độ dịch chuyển tối đa 3 bpm/tuần.
    /// </summary>
    ThresholdRecommendationDto ComputeAdaptiveThresholds(
        string elderProfileId,
        double currentMin,
        double currentMax,
        IReadOnlyList<double> samples);
}
