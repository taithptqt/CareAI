namespace CareAI.Core.Entities;

public class HealthMeasurement
{
    public long Id { get; set; }
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string DeviceId { get; set; } = string.Empty;
    public string PacketId { get; set; } = string.Empty;
    public string MetricType { get; set; } = string.Empty; // HEART_RATE | BLOOD_PRESSURE | SPO2 | STEPS | FALL
    public double Value { get; set; }
    public string Unit { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public DateTime RecordedAt { get; set; } = DateTime.UtcNow;
}
