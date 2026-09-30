using System.Collections.Concurrent;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Notifications;
using FirebaseAdmin.Messaging;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Xunit.Sdk;

namespace CareAI.UnitTests;

[Collection("SqlServerIntegration")]
public class QuorumSlaTests
{
    [Fact]
    public void FirebaseMessage_CarriesStringDataAndAndroidHighPriority()
    {
        var item = new NotificationOutbox
        {
            Id = "outbox", IncidentId = "incident", AlertCycleNumber = 2,
            PushToken = "test-token", Title = "Urgent", Body = "Help",
            DataPayloadJson = "{\"incidentId\":\"incident\",\"siren\":true,\"reminderNumber\":1}"
        };
        var message = FirebasePushSender.BuildMessage(item);
#pragma warning disable CS0618 // Current caregiver registration stores FCM tokens.
        Assert.Equal("test-token", message.Token);
#pragma warning restore CS0618
        Assert.Equal(Priority.High, message.Android.Priority);
        Assert.Null(message.Notification);
        Assert.Equal("Urgent", message.Data["title"]);
        Assert.Equal("Help", message.Data["body"]);
        Assert.False(message.Android.DirectBootOk);
        Assert.Equal("true", message.Data["siren"]);
        Assert.Equal("1", message.Data["reminderNumber"]);
        Assert.Equal("2", message.Data["alertCycleNumber"]);
        Assert.Equal("outbox", message.Data["outboxId"]);
    }

    [Fact]
    public void StatusPush_UsesDataOnlyHighPriority_ToStopBackgroundSiren()
    {
        var message = FirebasePushSender.BuildMessage(new NotificationOutbox
        {
            Id = "status", IncidentId = "incident", AlertCycleNumber = 2,
            PushToken = "test-token", Title = "Đã tiếp nhận", Body = "Người thân đã ACK",
            DataPayloadJson = "{\"incidentId\":\"incident\",\"eventType\":\"ACKNOWLEDGED\",\"siren\":false}"
        });
        Assert.Null(message.Notification);
        Assert.Equal(Priority.High, message.Android.Priority);
        Assert.Equal("ACKNOWLEDGED", message.Data["eventType"]);
        Assert.Equal("false", message.Data["siren"]);
    }

    [Fact]
    public async Task FirebaseSenderWithoutProject_DoesNotClaimDelivery()
    {
        var config = new ConfigurationBuilder().AddInMemoryCollection(
            new Dictionary<string, string?> { ["Firebase:ProjectId"] = "" }).Build();
        var sender = new FirebasePushSender(config, NullLogger<FirebasePushSender>.Instance);
        var result = await sender.SendAsync(new NotificationOutbox
        {
            PushToken = "test", DataPayloadJson = "{}", Title = "Test", Body = "Test"
        }, CancellationToken.None);
        Assert.Equal(PushSendDisposition.ConfigurationUnavailable, result.Disposition);
    }

    [Fact]
    public async Task Quorum_AllActiveRecipientsAccepted_OnlyThenMarkedSent()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now, twoCaregivers: true);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        var sender = new FakeSender((item, _) =>
            new(PushSendDisposition.Accepted, MessageId: $"fcm-{item.Id}"));

        await Dispatch(db, sender).DispatchDueAsync(now);
        Assert.Equal(2, sender.Calls.Count);
        Assert.All(db.NotificationOutboxes, n =>
        {
            Assert.Equal("SENT", n.Status);
            Assert.Equal($"fcm-{n.Id}", n.ProviderMessageId);
            Assert.True(n.SentAt >= now && n.SentAt <= DateTime.UtcNow);
        });
        await Dispatch(db, sender).DispatchDueAsync(now.AddSeconds(1));
        Assert.Equal(2, sender.Calls.Count);
    }

    [Fact]
    public async Task Quorum_StartsBothNetworkSendsBeforeWaitingForEither()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now, twoCaregivers: true);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        var bothStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var started = 0;
        var sender = new AsyncFakeSender(async (_, ct) =>
        {
            if (Interlocked.Increment(ref started) == 2) bothStarted.TrySetResult();
            await release.Task.WaitAsync(ct);
            return new(PushSendDisposition.Accepted, MessageId: "accepted");
        });
        var dispatch = Dispatch(db, sender).DispatchDueAsync(now);
        await bothStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.False(dispatch.IsCompleted);
        release.TrySetResult();
        await dispatch;
        Assert.Equal(2, started);
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync(n => n.Status == "SENT"));
    }

    [Fact]
    public async Task FailedAndUnregisteredTokens_AreHandledIndependently()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now, twoCaregivers: true);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        var sender = new FakeSender((item, _) => item.RecipientCaregiverId == "caregiver-a"
            ? new(PushSendDisposition.InvalidToken, ErrorCode: "FCM_UNREGISTERED")
            : new(PushSendDisposition.Accepted, MessageId: "accepted"));

        await Dispatch(db, sender).DispatchDueAsync(now);
        Assert.Equal("FAILED", db.NotificationOutboxes.Single(n => n.RecipientCaregiverId == "caregiver-a").Status);
        Assert.Equal("SENT", db.NotificationOutboxes.Single(n => n.RecipientCaregiverId == "caregiver-b").Status);
        Assert.False(db.CaregiverPushTokens.Single(t => t.CaregiverId == "caregiver-a").IsActive);
        Assert.True(db.CaregiverPushTokens.Single(t => t.CaregiverId == "caregiver-b").IsActive);
    }

    [Fact]
    public async Task TransientFailure_RetriesAfterBackoff_AndStopsAfterFiveAttempts()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        var sender = new FakeSender((_, _) => new(PushSendDisposition.Retryable, ErrorCode: "FCM_Unavailable"));
        var dispatcher = Dispatch(db, sender);
        for (var attempt = 1; attempt <= 5; attempt++)
        {
            await dispatcher.DispatchDueAsync(now);
            var item = db.NotificationOutboxes.Single();
            Assert.Equal(attempt, item.RetryCount);
            if (attempt < 5)
            {
                Assert.Equal("PENDING", item.Status);
                Assert.True(item.NextRetryAt > now);
                await dispatcher.DispatchDueAsync(now);
                Assert.Equal(attempt, sender.Calls.Count);
                now = item.NextRetryAt!.Value;
            }
        }
        Assert.Equal("FAILED", db.NotificationOutboxes.Single().Status);
        Assert.Equal(5, sender.Calls.Count);
    }

    [Fact]
    public async Task MissingFirebaseConfiguration_LeavesOutboxPendingWithoutFalseSuccess()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        var sender = new FakeSender((_, _) =>
            new(PushSendDisposition.ConfigurationUnavailable, ErrorCode: "FIREBASE_PROJECT_MISSING"));
        await Dispatch(db, sender).DispatchDueAsync(now);
        var item = db.NotificationOutboxes.Single();
        Assert.Equal("PENDING", item.Status);
        Assert.Null(item.SentAt);
        Assert.Equal(0, item.RetryCount);
        Assert.Equal(now.AddMinutes(5), item.NextRetryAt);
    }

    [Fact]
    public async Task MalformedPayload_IsPermanentFailure()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now);
        QueueInitial(db, now);
        await db.SaveChangesAsync();
        db.NotificationOutboxes.Single().DataPayloadJson = "not-json";
        await db.SaveChangesAsync();
        Assert.ThrowsAny<System.Text.Json.JsonException>(() =>
            FirebasePushSender.BuildMessage(db.NotificationOutboxes.Single()));
        var fake = new FakeSender((_, _) =>
            new(PushSendDisposition.PermanentFailure, ErrorCode: "INVALID_OUTBOX_PAYLOAD"));
        await Dispatch(db, fake).DispatchDueAsync(now);
        Assert.Equal("FAILED", db.NotificationOutboxes.Single().Status);
        Assert.Single(fake.Calls);
    }

    [Fact]
    public async Task AckedIncident_CancelsQueuedSiren_ButAllowsStatusNotice()
    {
        await using var db = NewMemoryDb();
        var now = DateTime.UtcNow;
        await SeedAsync(db, now);
        QueueInitial(db, now);
        var status = new NotificationOutbox
        {
            IncidentId = "incident", RecipientCaregiverId = "caregiver-a",
            PushToken = "token-a", Title = "ACK", Body = "Accepted",
            DataPayloadJson = "{\"eventType\":\"ACKNOWLEDGED\",\"siren\":false}", CreatedAt = now
        };
        db.NotificationOutboxes.Add(status);
        db.Incidents.Single().Status = IncidentStatus.Acknowledged;
        await db.SaveChangesAsync();
        var sender = new FakeSender((_, _) => new(PushSendDisposition.Accepted, MessageId: "ok"));

        await Dispatch(db, sender).DispatchDueAsync(now);
        Assert.Single(sender.Calls);
        Assert.Equal("CANCELLED", db.NotificationOutboxes.Single(n => n.Title == "Urgent").Status);
        Assert.Equal("SENT", status.Status);
    }

    [Fact]
    public async Task SlaAtSixtySeconds_QueuesOneReminderPerCaregiver_ThenStopsAfterAck()
    {
        await using var db = NewMemoryDb();
        var start = DateTime.UtcNow;
        await SeedAsync(db, start, twoCaregivers: true);
        var engine = Sla(db);
        await engine.CheckDueAsync(start.AddSeconds(59));
        Assert.Null(db.Incidents.Single().SlaBreachedAt);
        await engine.CheckDueAsync(start.AddSeconds(60));
        var incident = db.Incidents.Single();
        Assert.Equal(start.AddSeconds(60), incident.SlaBreachedAt);
        Assert.Equal(1, incident.ReminderCount);
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());
        Assert.Single(db.IncidentTimelineEvents.Where(e => e.EventType == "SLA_BREACHED"));
        await engine.CheckDueAsync(start.AddSeconds(60));
        Assert.Equal(2, await db.NotificationOutboxes.CountAsync());

        await engine.CheckDueAsync(start.AddSeconds(120));
        Assert.Equal(2, incident.ReminderCount);
        Assert.Equal(4, await db.NotificationOutboxes.CountAsync());
        incident.Status = IncidentStatus.Acknowledged;
        incident.AcknowledgedAt = start.AddSeconds(125);
        await db.SaveChangesAsync();
        await engine.CheckDueAsync(start.AddSeconds(180));
        Assert.Equal(4, await db.NotificationOutboxes.CountAsync());
        Assert.Equal(2, incident.ReminderCount);
    }

    [Fact]
    public async Task ZeroReminderPolicy_RecordsBreachWithoutQueuingPush()
    {
        await using var db = NewMemoryDb();
        var start = DateTime.UtcNow;
        await SeedAsync(db, start);
        await Sla(db, maxReminders: 0).CheckDueAsync(start.AddSeconds(60));
        Assert.NotNull(db.Incidents.Single().SlaBreachedAt);
        Assert.Equal(0, db.Incidents.Single().ReminderCount);
        Assert.Empty(db.NotificationOutboxes);
        Assert.Single(db.IncidentTimelineEvents);
    }

    [Fact]
    public async Task ReminderPolicy_StopsAtConfiguredMaximum()
    {
        await using var db = NewMemoryDb();
        var start = DateTime.UtcNow;
        await SeedAsync(db, start);
        var sla = Sla(db);
        foreach (var seconds in new[] { 60, 120, 180, 240 })
            await sla.CheckDueAsync(start.AddSeconds(seconds));
        Assert.Equal(3, db.Incidents.Single().ReminderCount);
        Assert.Null(db.Incidents.Single().NextReminderAt);
        Assert.Equal(3, await db.NotificationOutboxes.CountAsync());
        Assert.Single(db.IncidentTimelineEvents.Where(e => e.EventType == "SLA_BREACHED"));
    }

    [Fact]
    public async Task SqlServer_TwoSlaAndDispatchWorkers_DoNotDuplicateOutboxOrSend()
    {
        var configured = Environment.GetEnvironmentVariable("CAREAI_TEST_SQL_CONNECTION_STRING");
        if (string.IsNullOrWhiteSpace(configured))
            return;

        var name = $"CareAI_Quorum_{Guid.NewGuid():N}";
        var master = new SqlConnectionStringBuilder(configured) { InitialCatalog = "master" };
        var test = new SqlConnectionStringBuilder(configured) { InitialCatalog = name };
        await using (var conn = new SqlConnection(master.ConnectionString))
        {
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"CREATE DATABASE [{name}]";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }
        try
        {
            await DatabaseMigrationHelper.InitializeDatabaseAsync(test.ConnectionString);
            await DatabaseMigrationHelper.InitializeDatabaseAsync(test.ConnectionString);
            var start = DateTime.UtcNow;
            await using (var seed = NewSqlDb(test.ConnectionString))
                await SeedAsync(seed, start, twoCaregivers: true);
            await using var slaA = NewSqlDb(test.ConnectionString);
            await using var slaB = NewSqlDb(test.ConnectionString);
            await Task.WhenAll(Sla(slaA).CheckDueAsync(start.AddSeconds(60)),
                Sla(slaB).CheckDueAsync(start.AddSeconds(60)));
            await using (var verify = NewSqlDb(test.ConnectionString))
            {
                Assert.Single(verify.IncidentTimelineEvents.Where(e => e.EventType == "SLA_BREACHED"));
                Assert.Equal(2, await verify.NotificationOutboxes.CountAsync());
            }
            var sender = new FakeSender((item, _) =>
                new(PushSendDisposition.Accepted, MessageId: $"fcm-{item.Id}"));
            await using var dispatchA = NewSqlDb(test.ConnectionString);
            await using var dispatchB = NewSqlDb(test.ConnectionString);
            await Task.WhenAll(Dispatch(dispatchA, sender).DispatchDueAsync(start.AddSeconds(61)),
                Dispatch(dispatchB, sender).DispatchDueAsync(start.AddSeconds(61)));
            await using (var verify = NewSqlDb(test.ConnectionString))
            {
                Assert.Equal(2, await verify.NotificationOutboxes.CountAsync(n => n.Status == "SENT"));
                Assert.Equal(2, sender.Calls.Count);
                Assert.All(await verify.NotificationOutboxes.ToListAsync(), n => Assert.NotNull(n.ProviderMessageId));
            }
        }
        finally
        {
            await using var conn = new SqlConnection(master.ConnectionString);
            await conn.OpenAsync();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = $"ALTER DATABASE [{name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [{name}]";
            cmd.CommandTimeout = 120;
            await cmd.ExecuteNonQueryAsync();
        }
    }

    private static NotificationDispatchEngine Dispatch(CareAiDbContext db, IPushSender sender) =>
        new(db, sender, NullLogger<NotificationDispatchEngine>.Instance);

    private static AlertSlaEngine Sla(CareAiDbContext db, int maxReminders = 3) =>
        new(db, Options.Create(new AlertingOptions { MaxReminders = maxReminders }),
            NullLogger<AlertSlaEngine>.Instance);

    private static CareAiDbContext NewMemoryDb() => new(new DbContextOptionsBuilder<CareAiDbContext>()
        .UseInMemoryDatabase($"Quorum_{Guid.NewGuid():N}").Options);

    private static CareAiDbContext NewSqlDb(string connection) => new(
        new DbContextOptionsBuilder<CareAiDbContext>()
            .UseSqlServer(connection, sql => sql.CommandTimeout(120)).Options);

    private static async Task SeedAsync(CareAiDbContext db, DateTime start, bool twoCaregivers = false)
    {
        db.ElderProfiles.Add(new ElderProfile { Id = "elder", FullName = "Test Elder" });
        db.Incidents.Add(new Incident
        {
            Id = "incident", ElderProfileId = "elder", TriggeredByDeviceId = "device",
            EmergencyType = EmergencyType.Tachycardia, Severity = IncidentSeverity.Critical,
            Status = IncidentStatus.Open, AlertStartedAt = start,
            AlertDeadlineAt = start.AddSeconds(60), TriggeredAt = start
        });
        foreach (var suffix in twoCaregivers ? new[] { "a", "b" } : new[] { "a" })
        {
            var caregiverId = $"caregiver-{suffix}";
            db.Caregivers.Add(new Caregiver
            {
                Id = caregiverId, FullName = $"Caregiver {suffix}", PhoneNumber = suffix,
                Email = $"{suffix}@example.test", PasswordHash = "test"
            });
            db.ElderCaregivers.Add(new ElderCaregiver
            {
                Id = $"link-{suffix}", ElderProfileId = "elder",
                CaregiverId = caregiverId, IsActive = true
            });
            db.CaregiverPushTokens.Add(new CaregiverPushToken
            {
                Id = $"push-{suffix}", CaregiverId = caregiverId,
                PushToken = $"token-{suffix}", IsActive = true
            });
        }
        await db.SaveChangesAsync();
    }

    private static void QueueInitial(CareAiDbContext db, DateTime now)
    {
        foreach (var token in db.CaregiverPushTokens)
            db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = "incident", AlertCycleNumber = 1,
                RecipientCaregiverId = token.CaregiverId,
                PushToken = token.PushToken, Title = "Urgent", Body = "Help",
                DataPayloadJson = "{\"incidentId\":\"incident\",\"siren\":true,\"priority\":\"HIGH\"}",
                CreatedAt = now
            });
    }

    private sealed class FakeSender : IPushSender
    {
        private readonly Func<NotificationOutbox, int, PushSendResult> _result;
        private int _attempts;
        public ConcurrentBag<string> Calls { get; } = [];

        public FakeSender(Func<NotificationOutbox, int, PushSendResult> result) => _result = result;

        public Task<PushSendResult> SendAsync(NotificationOutbox item, CancellationToken ct)
        {
            Calls.Add(item.Id);
            return Task.FromResult(_result(item, Interlocked.Increment(ref _attempts)));
        }
    }

    private sealed class AsyncFakeSender : IPushSender
    {
        private readonly Func<NotificationOutbox, CancellationToken, Task<PushSendResult>> _send;
        public AsyncFakeSender(Func<NotificationOutbox, CancellationToken, Task<PushSendResult>> send) =>
            _send = send;
        public Task<PushSendResult> SendAsync(NotificationOutbox item, CancellationToken ct) =>
            _send(item, ct);
    }
}
