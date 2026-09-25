namespace CareAI.Core.Entities;

public class NotificationOutbox
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string IncidentId { get; set; } = string.Empty;
    public int AlertCycleNumber { get; set; } = 1;
    public Incident Incident { get; set; } = null!;

    public string? RecipientCaregiverId { get; set; }
    public string PushToken { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public string DataPayloadJson { get; set; } = string.Empty;
    public string Status { get; set; } = "PENDING"; // PENDING | SENT | FAILED
    public int RetryCount { get; set; } = 0;
    public DateTime? NextRetryAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? SentAt { get; set; }
    public DateTime? LeaseExpiresAt { get; set; }
    public string? ProviderMessageId { get; set; }
    public string? LastErrorCode { get; set; }
    public byte[]? RowVersion { get; set; }
}
