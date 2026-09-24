namespace CareAI.Core.DTOs;

public record HealthSampleDto(string MetricType, double Value, string? Unit, DateTime Timestamp);

public record SosPacketRequest(
    string PacketId,
    string? EventId,
    string EmergencyType,
    string? Severity,
    DateTime? TriggeredAt,
    string? GPSLocation,
    List<HealthSampleDto>? Samples
);

public record AcknowledgeIncidentRequest(string? Notes);
public record ResolveIncidentRequest(string ResolutionNotes);

public record IncidentResponseDto(
    string Id,
    string ElderProfileId,
    string ElderName,
    string TriggeredByDeviceId,
    string EmergencyType,
    string Severity,
    string Status,
    DateTime TriggeredAt,
    DateTime? AcknowledgedAt,
    string? AcknowledgedByCaregiverId,
    DateTime? ResolvedAt,
    string? ResolvedByCaregiverId,
    string? ResolutionNotes,
    List<IncidentTimelineDto> Timeline
);

public record IncidentTimelineDto(string EventType, string Description, DateTime RecordedAt);
