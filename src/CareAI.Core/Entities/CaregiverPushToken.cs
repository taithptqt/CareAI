namespace CareAI.Core.Entities;

public class CaregiverPushToken
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string CaregiverId { get; set; } = string.Empty;
    public Caregiver Caregiver { get; set; } = null!;

    public string PushToken { get; set; } = string.Empty;
    public string? DeviceModel { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastUsedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DeactivatedAt { get; set; }
    public string? DeactivationReason { get; set; }
}
