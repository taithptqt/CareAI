using CareAI.Core.Enums;

namespace CareAI.Core.Entities;

public class ElderCaregiver
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string CaregiverId { get; set; } = string.Empty;
    public Caregiver Caregiver { get; set; } = null!;

    public CaregiverRole Role { get; set; } = CaregiverRole.Secondary;
    public bool IsActive { get; set; } = true;
    public DateTime AssignedAt { get; set; } = DateTime.UtcNow;
}
