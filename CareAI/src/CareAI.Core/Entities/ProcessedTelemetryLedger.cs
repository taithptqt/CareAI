namespace CareAI.Core.Entities;

public class ProcessedTelemetryLedger
{
    public string DeviceId { get; set; } = string.Empty;
    public string PacketId { get; set; } = string.Empty;
    public string? IncidentId { get; set; }
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}
