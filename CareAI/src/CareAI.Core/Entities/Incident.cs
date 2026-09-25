using CareAI.Core.Enums;

namespace CareAI.Core.Entities;

public class Incident
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string TriggeredByDeviceId { get; set; } = string.Empty;
    public string EmergencyType { get; set; } = string.Empty; // FALL | MANUAL_SOS | TACHYCARDIA | HYPERTENSION | STALE_OFFLINE
    public IncidentSeverity Severity { get; set; } = IncidentSeverity.Critical;
    public IncidentStatus Status { get; set; } = IncidentStatus.Open;

    public DateTime TriggeredAt { get; set; } = DateTime.UtcNow;
    // Snapshot at the first trigger. These values must not follow later profile or telemetry edits.
    public double? HeartRateBpm { get; set; }
    public double? SpO2Percent { get; set; }
    public double? BpSystolic { get; set; }
    public double? BpDiastolic { get; set; }
    public DateTime? VitalsMeasuredAt { get; set; }
    public string? GpsLocation { get; set; }
    public string? CurrentGpsLocation { get; set; }
    public DateTime? CurrentGpsMeasuredAt { get; set; }
    public bool? CurrentGpsIsSimulated { get; set; }
    public double? CurrentGpsAccuracyMeters { get; set; }
    public string? HomeAddressSnapshot { get; set; }

    // Current alert round. Earlier rounds remain recorded in the timeline.
    public int AlertCycleNumber { get; set; } = 1;
    public DateTime? AlertStartedAt { get; set; }
    public DateTime? AlertDeadlineAt { get; set; }
    public DateTime? SlaBreachedAt { get; set; }
    public int ReminderCount { get; set; }
    public DateTime? NextReminderAt { get; set; }
    public DateTime? AcknowledgedAt { get; set; }
    public string? AcknowledgedByCaregiverId { get; set; }
    public DateTime? ResolvedAt { get; set; }
    public string? ResolvedByCaregiverId { get; set; }
    public string? ResolutionNotes { get; set; }
    // Tracks the current connectivity episode; timeline keeps each transition permanently.
    public DateTime? ConnectivityLostAt { get; set; }
    // The latest critical sample and the sample accepted by the caregiver are distinct
    // from the immutable vitals snapshot captured when this incident was created.
    public double? LatestCriticalHeartRateBpm { get; set; }
    public string? LatestCriticalRuleCode { get; set; }
    public double? AcknowledgedCriticalHeartRateBpm { get; set; }
    public string? AcknowledgedCriticalRuleCode { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Khóa lạc quan chống xung đột đồng thời (Optimistic Concurrency Control)
    public byte[]? RowVersion { get; set; }

    // Dấu vết pháp y y tế (Medical Forensic Audit Trail)
    public ICollection<IncidentTimelineEvent> TimelineEvents { get; set; } = new List<IncidentTimelineEvent>();
}
