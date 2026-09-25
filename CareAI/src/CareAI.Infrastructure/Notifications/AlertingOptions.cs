namespace CareAI.Infrastructure.Notifications;

public class AlertingOptions
{
    public const string SectionName = "Alerting";
    public int ReminderIntervalSeconds { get; set; } = 60;
    public int MaxReminders { get; set; } = 3;
}
