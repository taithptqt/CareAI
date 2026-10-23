namespace CareAI.Core.Entities.Admin;

public sealed class AdminCommandRecord
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ActorId { get; set; } = "";
    public string RequestId { get; set; } = "";
    public string PayloadFingerprint { get; set; } = "";
    public string TargetId { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
