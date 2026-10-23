using System.ComponentModel.DataAnnotations;

namespace CareAI.Core.DTOs;

public sealed class SubmitFeedbackRequest(string requestId, string category, string subject, string message)
{
    [Required, RegularExpression(@"^[a-fA-F0-9]{32}$")] public string RequestId { get; init; } = requestId;
    [Required, RegularExpression("^(Bug|Suggestion|Other)$")] public string Category { get; init; } = category;
    [Required, StringLength(120, MinimumLength = 3)] public string Subject { get; init; } = subject;
    [Required, StringLength(3000, MinimumLength = 10)] public string Message { get; init; } = message;
}

public sealed record CustomerFeedbackDto(string Id, string Category, string Subject, string Message, DateTimeOffset CreatedAtUtc,
    string Status = "New", string? AdminReply = null, DateTimeOffset? RepliedAtUtc = null);
public sealed record AdminFeedbackDto(string Id, string CaregiverId, string SenderName,
    string Category, string Subject, string Message, DateTimeOffset CreatedAtUtc,
    string Status = "New", string? AdminReply = null, string Version = "");
