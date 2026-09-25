namespace CareAI.Core.Entities;

public class HealthInsight
{
    public long Id { get; set; }
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;
    public string DeviceId { get; set; } = string.Empty;
    public string InsightType { get; set; } = string.Empty;
    public DateTime WindowEndUtc { get; set; }
    public double ObservedValue { get; set; }
    public double BaselineValue { get; set; }
    public double PValue { get; set; }
    public string Description { get; set; } = string.Empty;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
