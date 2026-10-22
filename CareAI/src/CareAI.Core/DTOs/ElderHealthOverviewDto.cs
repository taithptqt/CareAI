namespace CareAI.Core.DTOs;

// A missing daily steps sample is unknown, rather than a measured zero.
public record ElderHealthOverviewDto(
    VitalSignDto? LatestHeartRate,
    VitalSignDto? LatestSpO2,
    int? TodaySteps,
    DateTime? StepsMeasuredAt,
    DateTime? LastSyncedAt = null);
