namespace CareAI.Core.Entities;

public sealed class CustomerFeedback
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string CaregiverId { get; set; } = "";
    public Caregiver Caregiver { get; set; } = null!;
    public string RequestId { get; set; } = "";
    public string Category { get; set; } = "Other";
    public string Subject { get; set; } = "";
    public string Message { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public string Status { get; set; } = "New";
    public string? AdminReply { get; set; }
    public DateTime? RepliedAtUtc { get; set; }
}
