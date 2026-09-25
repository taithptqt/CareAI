namespace CareAI.Core.Entities;

public class ClinicalRuleCooldown
{
    public string ElderProfileId { get; set; } = string.Empty;
    public string RuleCode { get; set; } = string.Empty;
    public DateTime LastAlertAt { get; set; }
    public string LastIncidentId { get; set; } = string.Empty;
}
