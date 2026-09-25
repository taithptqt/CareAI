using System.Text.Json;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.Notifications;

public class AlertSlaEngine
{
    private readonly CareAiDbContext _db;
    private readonly AlertingOptions _options;
    private readonly ILogger<AlertSlaEngine> _logger;

    public AlertSlaEngine(CareAiDbContext db, IOptions<AlertingOptions> options,
        ILogger<AlertSlaEngine> logger)
    {
        _db = db;
        _options = options.Value;
        _logger = logger;
    }

    public async Task CheckDueAsync(DateTime nowUtc, CancellationToken ct = default)
    {
        if (nowUtc.Kind != DateTimeKind.Utc)
            throw new ArgumentException("SLA scan time must be UTC.", nameof(nowUtc));
        var maxReminders = Math.Clamp(_options.MaxReminders, 0, 20);
        var interval = TimeSpan.FromSeconds(Math.Clamp(_options.ReminderIntervalSeconds, 30, 3600));
        var dueIds = await _db.Incidents.AsNoTracking()
            .Where(i => i.Status == IncidentStatus.Open && i.Severity == IncidentSeverity.Critical &&
                i.AlertDeadlineAt != null && i.AlertDeadlineAt <= nowUtc &&
                (i.SlaBreachedAt == null ||
                 (i.ReminderCount < maxReminders && i.NextReminderAt != null &&
                  i.NextReminderAt <= nowUtc)))
            .OrderBy(i => i.AlertDeadlineAt).Take(50).Select(i => i.Id).ToListAsync(ct);

        foreach (var id in dueIds)
        {
            var incident = await _db.Incidents.FirstOrDefaultAsync(i => i.Id == id, ct);
            if (incident == null || incident.Status != IncidentStatus.Open ||
                incident.Severity != IncidentSeverity.Critical ||
                incident.AlertDeadlineAt > nowUtc) continue;

            var firstBreach = !incident.SlaBreachedAt.HasValue;
            if (firstBreach)
            {
                incident.SlaBreachedAt = nowUtc;
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = id, AlertCycleNumber = incident.AlertCycleNumber,
                    EventType = "SLA_BREACHED",
                    Description = "Chưa có người thân tiếp nhận trong 60 giây kể từ khi cảnh báo Critical được lưu.",
                    RecordedAt = nowUtc
                });
            }

            if (incident.ReminderCount < maxReminders &&
                (firstBreach || incident.NextReminderAt <= nowUtc))
            {
                incident.ReminderCount++;
                incident.NextReminderAt = incident.ReminderCount < maxReminders
                    ? nowUtc.Add(interval) : null;
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = id, AlertCycleNumber = incident.AlertCycleNumber,
                    EventType = "SLA_REMINDER_QUEUED",
                    Description = $"Nhắc lại cảnh báo Critical lần {incident.ReminderCount}; chưa có ACK.",
                    RecordedAt = nowUtc
                });
                await QueueReminderAsync(incident, nowUtc, ct);
            }
            incident.UpdatedAt = nowUtc;
            try
            {
                // RowVersion makes the incident update, audit event and reminder outbox atomic
                // against an ACK or another SLA worker.
                await _db.SaveChangesAsync(ct);
                _logger.LogWarning("[SLA] Critical incident {IncidentId} missed ACK deadline.", id);
            }
            catch (DbUpdateConcurrencyException)
            {
                _db.ChangeTracker.Clear();
                _logger.LogInformation("[SLA-RACE] Incident {IncidentId} changed before reminder commit.", id);
            }
        }
    }

    private async Task QueueReminderAsync(Incident incident, DateTime nowUtc, CancellationToken ct)
    {
        var recipients = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == incident.ElderProfileId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive), ec => ec.CaregiverId,
                t => t.CaregiverId, (ec, t) => new { ec.CaregiverId, t.PushToken }).ToListAsync(ct);
        foreach (var recipient in recipients)
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
                RecipientCaregiverId = recipient.CaregiverId, PushToken = recipient.PushToken,
                Title = "NHẮC LẠI CẢNH BÁO CẤP CỨU",
                Body = "Sự cố Critical chưa được người thân tiếp nhận. Vui lòng kiểm tra ngay.",
                DataPayloadJson = JsonSerializer.Serialize(new
                {
                    incidentId = incident.Id, elderProfileId = incident.ElderProfileId,
                    alertCycleNumber = incident.AlertCycleNumber,
                    eventType = "SLA_REMINDER", reminderNumber = incident.ReminderCount,
                    priority = "HIGH", siren = true
                }),
                Status = "PENDING", CreatedAt = nowUtc
            });
    }
}
