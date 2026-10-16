namespace CareAI.Infrastructure.Notifications;

public class AlertingOptions
{
    public const string SectionName = "Alerting";
    public int ReminderIntervalSeconds { get; set; } = 60;
    public int MaxReminders { get; set; } = 3;
    public int StableVitalsReminderMinutes { get; set; } = 15;
    public int MaxStableVitalsReminders { get; set; } = 2;
}

