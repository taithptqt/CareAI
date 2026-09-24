namespace CareAI.Core.DTOs;

public record TelemetrySampleDto(string MetricType, double Value, string? Unit, DateTime Timestamp);

public record TelemetryBatchRequest(
    string BatchId,
    List<TelemetrySampleDto> Samples
);

public record HeartbeatRequest(
    int? BatteryPercentage,
    bool? OnBody
);
