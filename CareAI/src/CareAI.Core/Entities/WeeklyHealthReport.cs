namespace CareAI.Core.Entities;

public class WeeklyHealthReport
{
    public long Id { get; set; }
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;
    public DateTime WeekStartUtc { get; set; }
    public DateTime WeekEndUtc { get; set; }
    public string Content { get; set; } = string.Empty;
    public string Source { get; set; } = "RULE_BASED";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class WeeklyReportNotification
{
    public long Id { get; set; }
    public long WeeklyHealthReportId { get; set; }
    public WeeklyHealthReport WeeklyHealthReport { get; set; } = null!;
    public string CaregiverPushTokenId { get; set; } = string.Empty;
    public string Status { get; set; } = "PENDING";
    public int RetryCount { get; set; }
    public DateTime NextAttemptUtc { get; set; } = DateTime.UtcNow;
    public DateTime? SentAt { get; set; }
    public byte[] RowVersion { get; set; } = Array.Empty<byte>();
}
