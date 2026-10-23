using System.ComponentModel.DataAnnotations;

namespace CareAI.Core.DTOs.Admin;

public sealed record AdminField(string Label, string Value);
public sealed record AdminRecord(string Id, string Title, string Subtitle, string Status, string Version,
    IReadOnlyList<AdminField> Fields);
public sealed record AdminTimelineItem(string EventType, DateTimeOffset AtUtc, string? ActorId, int? Cycle);
public sealed record AdminIncidentDetail(AdminIncidentSummary Incident, DateTimeOffset? AcknowledgedAtUtc,
    DateTimeOffset? ResolvedAtUtc, IReadOnlyList<AdminTimelineItem> Timeline);

public sealed class AdminCommandRequest
{
    [Required, StringLength(36)] public string RequestId { get; set; } = "";
    [Required, StringLength(40)] public string Action { get; set; } = "";
    [Required, StringLength(100)] public string TargetId { get; set; } = "";
    [Required, StringLength(128)] public string ExpectedVersion { get; set; } = "";
    [Required, StringLength(500, MinimumLength = 5)] public string Reason { get; set; } = "";
    [Required] public Dictionary<string, string> Values { get; set; } = [];
    [Required, StringLength(256)] public string ReauthPassword { get; set; } = "";
}
public sealed record AdminCommandResult(string TargetId, string Message);
public sealed record AdminAuditDetail(string Id, string ActorId, string Action, string TargetId,
    string Result, string Reason, string TraceId, DateTimeOffset OccurredAtUtc, string? ChangesJson);
