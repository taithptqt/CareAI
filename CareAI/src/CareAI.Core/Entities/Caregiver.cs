namespace CareAI.Core.Entities;

public class Caregiver
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string FullName { get; set; } = string.Empty;
    public string PhoneNumber { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string PasswordHash { get; set; } = string.Empty;
    public int FailedLoginAttempts { get; set; } = 0;
    public DateTime? LockoutEnd { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    // Navigation properties
    public ICollection<ElderCaregiver> ElderCaregivers { get; set; } = new List<ElderCaregiver>();
    public ICollection<CaregiverPushToken> PushTokens { get; set; } = new List<CaregiverPushToken>();
}
