namespace CareAI.Core.DTOs;

public record HealthSampleDto(string MetricType, double Value, string? Unit, DateTime Timestamp);

public record SosPacketRequest(
    string PacketId,
    string? EventId,
    string EmergencyType,
    string? Severity,
    DateTime? TriggeredAt,
    string? GPSLocation,
    List<HealthSampleDto>? Samples,
    bool? GpsIsSimulated = null,
    double? GpsAccuracyMeters = null
);

public record AcknowledgeIncidentRequest(string? Notes, string? RowVersion);
public record ResolveIncidentRequest(string ResolutionNotes, string? RowVersion);
public record AttachIncidentLocationRequest(string Coordinates, DateTime CapturedAt,
    bool IsSimulated = false, double? AccuracyMeters = null);

public record PagedResult<T>(
    List<T> Items,
    int Page,
    int PageSize,
    int TotalCount,
    int TotalPages
);

public record HeartRateSampleDto(
    DateTime Timestamp,
    double Value,
    string Unit,
    string? DeviceId = null
);

public record IncidentHeartRateWindowDto(
    DateTime IncidentTriggeredAt,
    DateTime WindowStartUtc,
    DateTime WindowEndUtc,
    List<HeartRateSampleDto> Samples
);

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
    List<IncidentTimelineDto> Timeline,
    string? RowVersion = null,
    IncidentSnapshotDto? Snapshot = null,
    IncidentAlertStateDto? AlertState = null,
    IncidentHeartRateWindowDto? HeartRateSeries = null
);

public record IncidentSnapshotDto(
    double? HeartRateBpm,
    double? SpO2Percent,
    double? BpSystolic,
    double? BpDiastolic,
    DateTime? VitalsMeasuredAt,
    string? GpsLocation,
    string? HomeAddress,
    string? CurrentGpsLocation = null,
    DateTime? CurrentGpsMeasuredAt = null,
    bool? CurrentGpsIsSimulated = null,
    double? CurrentGpsAccuracyMeters = null);

public record IncidentAlertStateDto(
    int CycleNumber,
    DateTime? StartedAt,
    DateTime? DeadlineAt,
    DateTime? SlaBreachedAt);

public record IncidentTimelineDto(
    string EventType,
    string Description,
    DateTime RecordedAt,
    string? ActorCaregiverId = null,
    int? AlertCycleNumber = null);
