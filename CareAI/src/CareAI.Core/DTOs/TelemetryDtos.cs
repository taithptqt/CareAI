namespace CareAI.Core.DTOs;

public record TelemetrySampleDto(string MetricType, double Value, string? Unit, DateTime Timestamp);

public record TelemetryBatchRequest(
    string BatchId,
    List<TelemetrySampleDto> Samples
);

public record UrgentHeartRateRequest(
    string PacketId,
    double HeartRateBpm,
    DateTime Timestamp
);

public record HeartbeatRequest(
    int? BatteryPercentage,
    bool? OnBody
);
