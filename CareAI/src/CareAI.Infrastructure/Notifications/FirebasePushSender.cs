using System.Text.Json;
using CareAI.Core.Entities;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Notifications;

public class FirebasePushSender : IPushSender
{
    private readonly string? _projectId;
    private readonly ILogger<FirebasePushSender> _logger;
    private readonly Lazy<FirebaseMessaging> _messaging;

    public FirebasePushSender(IConfiguration configuration, ILogger<FirebasePushSender> logger)
    {
        _projectId = configuration["Firebase:ProjectId"] ??
            Environment.GetEnvironmentVariable("GOOGLE_CLOUD_PROJECT");
        _logger = logger;
        _messaging = new Lazy<FirebaseMessaging>(() =>
        {
            var credentialsPath = configuration["Firebase:CredentialsPath"];
            GoogleCredential credential;
            if (!string.IsNullOrWhiteSpace(credentialsPath) && File.Exists(credentialsPath))
            {
#pragma warning disable CS0618
                credential = GoogleCredential.FromFile(credentialsPath);
#pragma warning restore CS0618
            }
            else
            {
                credential = GoogleCredential.GetApplicationDefault();
            }

            return FirebaseMessaging.GetMessaging(
                FirebaseApp.Create(new AppOptions
                {
                    Credential = credential,
                    ProjectId = _projectId
                }, $"careai-push-{Guid.NewGuid():N}"));
        });
    }

    public async Task<PushSendResult> SendAsync(NotificationOutbox outbox, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(_projectId))
            return new(PushSendDisposition.ConfigurationUnavailable, ErrorCode: "FIREBASE_PROJECT_MISSING");

        Message message;
        try
        {
            message = BuildMessage(outbox);
        }
        catch (Exception ex) when (ex is JsonException or ArgumentException)
        {
            return new(PushSendDisposition.PermanentFailure, ErrorCode: "INVALID_OUTBOX_PAYLOAD");
        }

        try
        {
            var messageId = await _messaging.Value.SendAsync(message, ct);
            return new(PushSendDisposition.Accepted, MessageId: messageId);
        }
        catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode == MessagingErrorCode.Unregistered)
        {
            return new(PushSendDisposition.InvalidToken, ErrorCode: "FCM_UNREGISTERED");
        }
        catch (FirebaseMessagingException ex) when (ex.MessagingErrorCode is
            MessagingErrorCode.InvalidArgument or MessagingErrorCode.SenderIdMismatch)
        {
            return new(PushSendDisposition.PermanentFailure,
                ErrorCode: $"FCM_{ex.MessagingErrorCode}");
        }
        catch (FirebaseMessagingException ex)
        {
            _logger.LogWarning("[FCM-RETRY] FCM rejected outbox {OutboxId}: {Code}",
                outbox.Id, ex.MessagingErrorCode);
            return new(PushSendDisposition.Retryable,
                ErrorCode: $"FCM_{ex.MessagingErrorCode}");
        }
        catch (InvalidOperationException)
        {
            return new(PushSendDisposition.ConfigurationUnavailable,
                ErrorCode: "FIREBASE_CREDENTIALS_UNAVAILABLE");
        }
        catch (FileNotFoundException)
        {
            return new(PushSendDisposition.ConfigurationUnavailable,
                ErrorCode: "FIREBASE_CREDENTIALS_UNAVAILABLE");
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[FCM-RETRY] Sender unavailable for outbox {OutboxId}: {ErrorType}",
                outbox.Id, ex.GetType().Name);
            return new(PushSendDisposition.Retryable, ErrorCode: "FCM_TRANSPORT_ERROR");
        }
    }

    public static Message BuildMessage(NotificationOutbox outbox)
    {
        if (string.IsNullOrWhiteSpace(outbox.PushToken))
            throw new ArgumentException("Push token is missing.", nameof(outbox));

        using var json = JsonDocument.Parse(outbox.DataPayloadJson);
        if (json.RootElement.ValueKind != JsonValueKind.Object)
            throw new JsonException("Outbox payload must be a JSON object.");
        var data = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var property in json.RootElement.EnumerateObject())
        {
            if (property.Value.ValueKind is JsonValueKind.Object or JsonValueKind.Array)
                continue;
            if (property.Value.ValueKind == JsonValueKind.Null)
                continue;
            data[property.Name] = property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString()! : property.Value.GetRawText();
        }
        data["outboxId"] = outbox.Id;
        data["alertCycleNumber"] = outbox.AlertCycleNumber.ToString();
        data["title"] = outbox.Title;
        data["body"] = outbox.Body;
        var urgent = data.TryGetValue("siren", out var siren) &&
            string.Equals(siren, "true", StringComparison.OrdinalIgnoreCase);
        var statusUpdate = data.TryGetValue("eventType", out var eventType) &&
            (eventType.Equals("ACKNOWLEDGED", StringComparison.OrdinalIgnoreCase) ||
             eventType.Equals("RESOLVED", StringComparison.OrdinalIgnoreCase));
        if (data.TryGetValue("priority", out var priority) &&
            (priority.Equals("HIGH", StringComparison.OrdinalIgnoreCase) ||
             priority.Equals("CRITICAL", StringComparison.OrdinalIgnoreCase)))
            urgent = true;

        // Caregiver registration currently stores FCM registration tokens; FID migration
        // requires a matching client change, so use the supported legacy target for now.
#pragma warning disable CS0618
        return new Message
        {
            Token = outbox.PushToken,
            // Data-only alerts reach the Flutter background handler. Android's
            // automatic notification path does not run it until the user taps.
            Notification = urgent || statusUpdate ? null : new Notification { Title = outbox.Title, Body = outbox.Body },
            Data = data,
            Android = new AndroidConfig
            {
                Priority = urgent || statusUpdate ? Priority.High : Priority.Normal,
                DirectBootOk = false,
                TimeToLive = urgent || statusUpdate ? TimeSpan.FromMinutes(5) : TimeSpan.FromHours(1)
            }
        };
#pragma warning restore CS0618
    }
}
