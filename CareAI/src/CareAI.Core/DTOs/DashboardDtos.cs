namespace CareAI.Core.DTOs;

public record VitalSignDto(string MetricType, double Value, string Unit, DateTime Timestamp, string StatusColor);

public record HeartRatePointDto(DateTime Timestamp, double Value);

public record HeartRate24hResponse(
    List<HeartRatePointDto> Points,
    double MinHeartRate,
    double MaxHeartRate,
    double AvgHeartRate,
    double LatestHeartRate
);

public record BloodPressurePointDto(DateTime Timestamp, double Systolic, double Diastolic);

public record BloodPressureHistoryResponse(
    List<BloodPressurePointDto> Points,
    double LatestSystolic,
    double LatestDiastolic,
    string Classification,
    string StatusColor
);

public record Spo2PointDto(DateTime Timestamp, double Value);

public record Spo224hResponse(
    List<Spo2PointDto> Points,
    double MinSpo2,
    double MaxSpo2,
    double AvgSpo2,
    double LatestSpo2,
    int DipsBelow95Count,
    string StatusColor
);

public record HourlyStepsDto(int Hour, int Steps);

public record HourlySteps24hResponse(
    List<HourlyStepsDto> HourlySteps,
    int TotalStepsToday,
    int PeakHour,
    int PeakSteps
);

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
    IncidentResponseDto? ActiveEmergency,
    VitalSignDto? DemoHeartRate = null,
    VitalSignDto? DemoSpO2 = null
);
