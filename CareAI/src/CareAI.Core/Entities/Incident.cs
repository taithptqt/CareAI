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
    public DateTime? AcknowledgedAt { get; set; }
    public string? AcknowledgedByCaregiverId { get; set; }
    public DateTime? ResolvedAt { get; set; }
    public string? ResolvedByCaregiverId { get; set; }
    public string? ResolutionNotes { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;

    // Khóa lạc quan chống xung đột đồng thời (Optimistic Concurrency Control)
    public byte[]? RowVersion { get; set; }

    // Dấu vết pháp y y tế (Medical Forensic Audit Trail)
    public ICollection<IncidentTimelineEvent> TimelineEvents { get; set; } = new List<IncidentTimelineEvent>();
}
