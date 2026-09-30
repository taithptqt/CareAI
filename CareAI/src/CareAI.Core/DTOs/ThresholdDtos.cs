namespace CareAI.Core.DTOs;

public record ThresholdRecommendationDto(
    string ElderProfileId,
    double CurrentMinBpm,
    double CurrentMaxBpm,
    double CalculatedP5,
    double CalculatedP95,
    double RecommendedMinBpm,
    double RecommendedMaxBpm,
    int TotalSamplesAnalyzed,
    DateTime AnalyzedAt,
    bool HasSufficientData,
    string ClinicalRationale
);

public record UpdateThresholdsRequest(
    double RestingHeartRateMin,
    double RestingHeartRateMax,
    double? NightHeartRateMin = null,
    double? NightHeartRateMax = null,
    string? SleepWindowStart = null,
    string? SleepWindowEnd = null
);

public record ThresholdResponse(
    string ElderProfileId,
    double RestingHeartRateMin,
    double RestingHeartRateMax,
    DateTime? UpdatedAt,
    double NightHeartRateMin = 40.0,
    double NightHeartRateMax = 90.0,
    string SleepWindowStart = "22:00",
    string SleepWindowEnd = "06:00",
    bool IsCurrentlySleepWindow = false
);

public record SleepSummaryResponse(
    string ElderProfileId,
    DateTime Date,
    int TotalSleepMinutes,
    DateTime? SleepStartTime,
    DateTime? SleepEndTime,
    int DeepSleepMinutes,
    int LightSleepMinutes,
    int WakeCount,
    string SleepQuality,
    string StatusColor
);
