namespace CareAI.Core.Entities.Admin;

// Separate lifecycle state keeps the existing caregiver schema compatible during deployment.
public sealed class CaregiverAdminState
{
    public string CaregiverId { get; set; } = "";
    public bool IsSuspended { get; set; }
    public int SecurityVersion { get; set; }
    public string Reason { get; set; } = "";
    public DateTime UpdatedAtUtc { get; set; }
    public byte[] RowVersion { get; set; } = [];
}
