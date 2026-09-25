namespace CareAI.Core.Entities;

/// <summary>One immutable, device-supplied JPEG attached to an emergency incident.</summary>
public class IncidentPhoto
{
    public string IncidentId { get; set; } = string.Empty;
    public Incident Incident { get; set; } = null!;
    public string DeviceId { get; set; } = string.Empty;
    public byte[] JpegBytes { get; set; } = [];
    public string Sha256 { get; set; } = string.Empty;
    public DateTime CapturedAt { get; set; } = DateTime.UtcNow;
    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}
