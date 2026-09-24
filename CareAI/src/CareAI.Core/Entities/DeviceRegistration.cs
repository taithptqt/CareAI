namespace CareAI.Core.Entities;

public class DeviceRegistration
{
    public string Id { get; set; } = Guid.NewGuid().ToString(); // DeviceId
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string DeviceTokenHash { get; set; } = string.Empty; // SHA-256 lowercase 64 chars
    public string DeviceType { get; set; } = string.Empty;       // Smartwatch | CompanionPhone
    public string FirmwareVersion { get; set; } = "1.0.0";
    public bool IsActive { get; set; } = true;
    public DateTime LastHeartbeat { get; set; } = DateTime.UtcNow;
    public DateTime RegisteredAt { get; set; } = DateTime.UtcNow;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
