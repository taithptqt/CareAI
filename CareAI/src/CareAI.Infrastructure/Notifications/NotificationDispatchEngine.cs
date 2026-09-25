using System.Text.Json;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Notifications;

public class NotificationDispatchEngine
{
    private static readonly TimeSpan LeaseDuration = TimeSpan.FromMinutes(2);
    private readonly CareAiDbContext _db;
    private readonly IPushSender _sender;
    private readonly ILogger<NotificationDispatchEngine> _logger;

    public NotificationDispatchEngine(CareAiDbContext db, IPushSender sender,
        ILogger<NotificationDispatchEngine> logger)
    {
        _db = db;
        _sender = sender;
        _logger = logger;
    }

    public async Task DispatchDueAsync(DateTime nowUtc, CancellationToken ct = default)
    {
        var ids = await _db.NotificationOutboxes.AsNoTracking()
            .Where(n => (n.Status == "PENDING" &&
                         (n.NextRetryAt == null || n.NextRetryAt <= nowUtc)) ||
                        (n.Status == "PROCESSING" && n.LeaseExpiresAt <= nowUtc))
            .OrderBy(n => n.CreatedAt).ThenBy(n => n.Id)
            .Take(50).Select(n => n.Id).ToListAsync(ct);

        var claimed = new List<NotificationOutbox>();
        foreach (var id in ids)
        {
            NotificationOutbox? item = null;
            try
            {
                item = await _db.NotificationOutboxes.Include(n => n.Incident)
                    .FirstOrDefaultAsync(n => n.Id == id, ct);
                if (item == null || !IsDue(item, nowUtc)) continue;
                item.Status = "PROCESSING";
                item.LeaseExpiresAt = nowUtc.Add(LeaseDuration);
                item.NextRetryAt = null;
                await _db.SaveChangesAsync(ct);
                claimed.Add(item);
            }
            catch (DbUpdateConcurrencyException)
            {
                if (item != null) _db.Entry(item).State = EntityState.Detached;
            }
        }

        // All claims are committed before network I/O. FCM requests then run concurrently;
        // EF queries and state updates remain sequential because DbContext is not thread-safe.
        var deliveries = new List<(NotificationOutbox Item, Task<PushSendResult> Send)>();
        foreach (var item in claimed)
        {
            try
            {
                if (!await HasActiveRecipientAsync(item, ct) ||
                    IsObsoleteSiren(item))
                {
                    item.Status = "CANCELLED";
                    item.LastErrorCode = "RECIPIENT_OR_ALERT_INACTIVE";
                    item.LeaseExpiresAt = null;
                    await _db.SaveChangesAsync(ct);
                }
                else
                    deliveries.Add((item, _sender.SendAsync(item, ct)));
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (DbUpdateConcurrencyException)
            {
                _db.Entry(item).State = EntityState.Detached;
                _logger.LogWarning("[FCM-STATE-RACE] Outbox {OutboxId} changed during dispatch.", item.Id);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("[FCM-RETRY] Unexpected sender failure for outbox {OutboxId}: {ErrorType}",
                    item.Id, ex.GetType().Name);
                ApplyResult(item, new(PushSendDisposition.Retryable, ErrorCode: "SENDER_EXCEPTION"), nowUtc);
                item.LeaseExpiresAt = null;
                await _db.SaveChangesAsync(ct);
            }
        }

        foreach (var (item, send) in deliveries)
        {
            try
            {
                var result = await send;
                var completedAt = result.Disposition == PushSendDisposition.Accepted
                    ? DateTime.UtcNow : nowUtc;
                ApplyResult(item, result, completedAt);
                if (result.Disposition == PushSendDisposition.InvalidToken)
                    await DisableInvalidTokenAsync(item, completedAt, ct);
                item.LeaseExpiresAt = null;
                await _db.SaveChangesAsync(ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested)
            {
                throw;
            }
            catch (DbUpdateConcurrencyException)
            {
                _db.Entry(item).State = EntityState.Detached;
                _logger.LogWarning("[FCM-STATE-RACE] Outbox {OutboxId} changed after send.", item.Id);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("[FCM-RETRY] Sender failure for outbox {OutboxId}: {ErrorType}",
                    item.Id, ex.GetType().Name);
                ApplyResult(item, new(PushSendDisposition.Retryable, ErrorCode: "SENDER_EXCEPTION"), nowUtc);
                item.LeaseExpiresAt = null;
                await _db.SaveChangesAsync(ct);
            }
        }
    }

    private static bool IsDue(NotificationOutbox item, DateTime now) =>
        (item.Status == "PENDING" && (item.NextRetryAt == null || item.NextRetryAt <= now)) ||
        (item.Status == "PROCESSING" && item.LeaseExpiresAt <= now);

    private async Task<bool> HasActiveRecipientAsync(NotificationOutbox item, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(item.RecipientCaregiverId)) return false;
        var caregiverId = item.RecipientCaregiverId;
        return await _db.CaregiverPushTokens.AnyAsync(t => t.IsActive &&
            t.CaregiverId == caregiverId && t.PushToken == item.PushToken, ct) &&
            await _db.ElderCaregivers.AnyAsync(ec => ec.IsActive &&
                ec.CaregiverId == caregiverId && ec.ElderProfileId == item.Incident.ElderProfileId, ct);
    }

    private static bool IsObsoleteSiren(NotificationOutbox item)
    {
        try
        {
            using var payload = JsonDocument.Parse(item.DataPayloadJson);
            var siren = payload.RootElement.TryGetProperty("siren", out var value) &&
                value.ValueKind == JsonValueKind.True;
            return siren && (item.Incident.Status != IncidentStatus.Open ||
                             item.Incident.AlertCycleNumber != item.AlertCycleNumber);
        }
        catch (JsonException)
        {
            // The sender will classify the malformed payload as a permanent failure.
            return false;
        }
    }

    private static void ApplyResult(NotificationOutbox item, PushSendResult result, DateTime now)
    {
        item.LastErrorCode = result.ErrorCode;
        switch (result.Disposition)
        {
            case PushSendDisposition.Accepted:
                item.Status = "SENT"; // FCM accepted it; the phone may receive it later.
                item.SentAt = now;
                item.ProviderMessageId = result.MessageId;
                item.NextRetryAt = null;
                break;
            case PushSendDisposition.InvalidToken:
            case PushSendDisposition.PermanentFailure:
                item.Status = "FAILED";
                item.NextRetryAt = null;
                break;
            case PushSendDisposition.ConfigurationUnavailable:
                item.Status = "PENDING";
                item.NextRetryAt = now.AddMinutes(5);
                break;
            case PushSendDisposition.Retryable:
                item.RetryCount++;
                if (item.RetryCount >= 5)
                {
                    item.Status = "FAILED";
                    item.NextRetryAt = null;
                }
                else
                {
                    item.Status = "PENDING";
                    var seconds = Math.Min(300, Math.Pow(2, item.RetryCount) * 2) +
                        Random.Shared.Next(1, 4);
                    if (result.ErrorCode == "FCM_QuotaExceeded") seconds = Math.Max(60, seconds);
                    item.NextRetryAt = now.AddSeconds(seconds);
                }
                break;
        }
    }

    private async Task DisableInvalidTokenAsync(NotificationOutbox item, DateTime now,
        CancellationToken ct)
    {
        var token = await _db.CaregiverPushTokens.FirstOrDefaultAsync(t =>
            t.CaregiverId == item.RecipientCaregiverId && t.PushToken == item.PushToken && t.IsActive, ct);
        if (token == null) return;
        token.IsActive = false;
        token.DeactivatedAt = now;
        token.DeactivationReason = "FCM_UNREGISTERED";
    }
}
