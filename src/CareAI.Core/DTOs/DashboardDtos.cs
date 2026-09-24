namespace CareAI.Core.DTOs;

public record VitalSignDto(string MetricType, double Value, string Unit, DateTime Timestamp, string StatusColor);

public record ElderDashboardResponse(
    string ElderProfileId,
    string FullName,
    int Age,
    string StatusBadgeColor, // GREEN | YELLOW | RED | GREY
    string DeviceStatus,     // ONLINE | OFFLINE | CHARGING
    VitalSignDto? LatestHeartRate,
    VitalSignDto? LatestBloodPressure,
    VitalSignDto? LatestSpO2,
    int TodaySteps,
    int StepGoal,
    string? LastKnownGpsLocation,
    DateTime? LastSyncedAt,
    IncidentResponseDto? ActiveEmergency
);
