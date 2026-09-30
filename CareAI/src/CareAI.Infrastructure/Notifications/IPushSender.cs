using CareAI.Core.Entities;

namespace CareAI.Infrastructure.Notifications;

public enum PushSendDisposition
{
    Accepted,
    Retryable,
    InvalidToken,
    PermanentFailure,
    ConfigurationUnavailable
}

public record PushSendResult(PushSendDisposition Disposition, string? MessageId = null,
    string? ErrorCode = null);

public interface IPushSender
{
    Task<PushSendResult> SendAsync(NotificationOutbox outbox, CancellationToken ct);
}
