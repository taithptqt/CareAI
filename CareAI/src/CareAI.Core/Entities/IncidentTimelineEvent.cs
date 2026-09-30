namespace CareAI.Core.Entities;

public class IncidentTimelineEvent
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string IncidentId { get; set; } = string.Empty;
    public Incident Incident { get; set; } = null!;

    public string EventType { get; set; } = string.Empty; // TRIGGERED | ACKNOWLEDGED | RESOLVED | NOTIFICATION_SENT
    public string Description { get; set; } = string.Empty;
    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
    public string? ActorCaregiverId { get; set; }
    public int? AlertCycleNumber { get; set; }
}
