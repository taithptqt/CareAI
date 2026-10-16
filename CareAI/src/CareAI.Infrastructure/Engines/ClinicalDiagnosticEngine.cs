using System.Text.Json;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Core.Interfaces;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Engines;

public class ClinicalDiagnosticEngine
{
    private static readonly TimeSpan Cooldown = TimeSpan.FromMinutes(10);
    private readonly CareAiDbContext _db;
    private readonly ILogger<ClinicalDiagnosticEngine> _logger;
    private readonly IAdaptiveThresholdService? _thresholdService;

    public ClinicalDiagnosticEngine(
        CareAiDbContext db,
        ILogger<ClinicalDiagnosticEngine> logger,
        IAdaptiveThresholdService? thresholdService = null)
    {
        _db = db;
        _logger = logger;
        _thresholdService = thresholdService;
    }

    public async Task<Incident?> EvaluateHeartRateSampleAsync(
        string elderProfileId, string deviceId, double heartRate, int? recentSteps = null,
        CancellationToken ct = default, bool saveChanges = true, DateTime? measuredAtUtc = null)
    {
        if (!double.IsFinite(heartRate) || heartRate <= 0 || heartRate > 300) return null;
        var now = DateTime.UtcNow;
        var measuredAt = measuredAtUtc ?? now;
        measuredAt = measuredAt.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(measuredAt, DateTimeKind.Utc) : measuredAt.ToUniversalTime();

        // Lấy ngưỡng thích nghi cá nhân hóa cho từng cụ (tự động phân tách Ngày và Đêm theo Khung giờ ngủ)
        double minBpm = 40.0;
        double maxBpm = 120.0;
        bool isNight = false;
        if (_thresholdService != null)
        {
            var thresholds = await _thresholdService.GetEffectiveThresholdsForTimeAsync(elderProfileId, measuredAt, ct);
            minBpm = thresholds.Min;
            maxBpm = thresholds.Max;
            isNight = thresholds.IsNight;
        }

        string? rule = null;
        string? emergencyType = null;
        var severity = IncidentSeverity.Low;
        string reason = string.Empty;
        if (heartRate >= 180)
        {
            rule = "HR_CRITICAL_HIGH";
            emergencyType = EmergencyType.Tachycardia;
            severity = IncidentSeverity.Critical;
            reason = $"Cảnh báo nhịp tim nguy kịch: {heartRate} bpm. Cần kiểm tra người cao tuổi ngay.";
        }
        else if (heartRate <= 35)
        {
            rule = "HR_CRITICAL_LOW";
            emergencyType = EmergencyType.Bradycardia;
            severity = IncidentSeverity.Critical;
            reason = $"Cảnh báo nhịp tim nguy kịch: {heartRate} bpm. Cần kiểm tra người cao tuổi ngay.";
        }
        else
        {
            var resting = recentSteps.HasValue
                ? recentSteps.Value is >= 0 and <= 10
                : await IsRestingAsync(elderProfileId, measuredAt, ct);
            if (resting && await HasSuddenRiseAsync(elderProfileId, measuredAt, heartRate, ct))
            {
                rule = "HR_RESTING_SURGE";
                emergencyType = EmergencyType.Surge;
                severity = IncidentSeverity.High;
                reason = $"Nhịp tim tăng ít nhất 15 bpm so với trung vị 5 phút lúc ít vận động: {heartRate} bpm.";
            }
            else if (heartRate > maxBpm && resting)
            {
                rule = "HR_RESTING_HIGH";
                emergencyType = EmergencyType.Tachycardia;
                severity = IncidentSeverity.High;
                var periodDesc = isNight ? "ban đêm (lúc ngủ)" : "lúc nghỉ";
                reason = $"Nhịp tim cao {periodDesc}: {heartRate} bpm (ngưỡng: {maxBpm} bpm).";
            }
            else if (heartRate < minBpm)
            {
                rule = "HR_LOW";
                emergencyType = EmergencyType.Bradycardia;
                severity = IncidentSeverity.High;
                var periodDesc = isNight ? "ban đêm (lúc ngủ)" : "ban ngày";
                reason = $"Nhịp tim thấp {periodDesc}: {heartRate} bpm (ngưỡng: {minBpm} bpm).";
            }
        }

        if (rule == null || emergencyType == null) return null;

        var active = await _db.Incidents.FirstOrDefaultAsync(i => i.ElderProfileId == elderProfileId &&
            (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);
        var cooldown = await _db.ClinicalRuleCooldowns.FindAsync([elderProfileId, rule], ct);
        var inCooldown = cooldown != null && now - cooldown.LastAlertAt < Cooldown;
        var critical = severity == IncidentSeverity.Critical;
        if (active != null)
        {
            var wasCritical = active.Severity == IncidentSeverity.Critical;
            var previousRule = active.LatestCriticalRuleCode;
            var reOpen = active.Status == IncidentStatus.Acknowledged && critical &&
                (!active.AcknowledgedAt.HasValue || measuredAt > active.AcknowledgedAt.Value) &&
                (active.AcknowledgedCriticalRuleCode != rule ||
                 !active.AcknowledgedCriticalHeartRateBpm.HasValue ||
                 (rule == "HR_CRITICAL_HIGH" && heartRate > active.AcknowledgedCriticalHeartRateBpm.Value) ||
                 (rule == "HR_CRITICAL_LOW" && heartRate < active.AcknowledgedCriticalHeartRateBpm.Value));
            var escalate = active.Status == IncidentStatus.Open && critical && !wasCritical;
            var distinctCritical = active.Status == IncidentStatus.Open && critical && wasCritical &&
                previousRule != rule && !inCooldown;

            if (critical && (active.Status != IncidentStatus.Acknowledged ||
                !active.AcknowledgedAt.HasValue || measuredAt > active.AcknowledgedAt.Value) &&
                (active.LatestCriticalRuleCode != rule ||
                (rule == "HR_CRITICAL_HIGH" && heartRate > active.LatestCriticalHeartRateBpm) ||
                (rule == "HR_CRITICAL_LOW" && heartRate < active.LatestCriticalHeartRateBpm)))
            {
                active.LatestCriticalRuleCode = rule;
                active.LatestCriticalHeartRateBpm = heartRate;
            }
            if (reOpen || escalate || distinctCritical)
            {
                active.Severity = IncidentSeverity.Critical;
                active.UpdatedAt = now;
                if (reOpen)
                {
                    active.AlertCycleNumber++;
                    active.Status = IncidentStatus.Open;
                    active.AcknowledgedAt = null;
                    active.AcknowledgedByCaregiverId = null;
                    active.AcknowledgedCriticalHeartRateBpm = null;
                    active.AcknowledgedCriticalRuleCode = null;
                    active.SlaBreachedAt = null;
                    active.ReminderCount = 0;
                    active.NextReminderAt = null;
                }
                if (reOpen || escalate)
                {
                    active.AlertStartedAt = now;
                    active.AlertDeadlineAt = now.AddSeconds(60);
                }
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = active.Id, AlertCycleNumber = active.AlertCycleNumber,
                    EventType = reOpen ? "CLINICAL_REESCALATION" : "CLINICAL_ESCALATION",
                    Description = reason, RecordedAt = now
                });
                await EnqueueQuorumAlertsAsync(active.Id, elderProfileId, emergencyType, reason,
                    active.AlertCycleNumber, now, true, ct);
                TouchCooldown(elderProfileId, rule, active.Id, now, cooldown);
                if (saveChanges) await _db.SaveChangesAsync(ct);
            }
            else if (critical && _db.Entry(active).State == EntityState.Modified && saveChanges)
                await _db.SaveChangesAsync(ct);
            return active;
        }

        // Repeated high warnings are suppressed after closure; new critical episodes always alert.
        if (inCooldown && !critical) return null;
        var homeAddress = await _db.ElderProfiles.Where(e => e.Id == elderProfileId)
            .Select(e => e.HomeAddress).FirstOrDefaultAsync(ct);
        var incident = new Incident
        {
            Id = Guid.NewGuid().ToString(), ElderProfileId = elderProfileId,
            TriggeredByDeviceId = deviceId, EmergencyType = emergencyType,
            Severity = severity, Status = IncidentStatus.Open,
            TriggeredAt = now, HeartRateBpm = heartRate, VitalsMeasuredAt = measuredAt,
            HomeAddressSnapshot = homeAddress,
            AlertStartedAt = critical ? now : null,
            AlertDeadlineAt = critical ? now.AddSeconds(60) : null,
            LatestCriticalHeartRateBpm = critical ? heartRate : null,
            LatestCriticalRuleCode = critical ? rule : null,
            CreatedAt = now, UpdatedAt = now
        };
        _db.Incidents.Add(incident);
        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
            EventType = "TRIGGERED", Description = reason, RecordedAt = now
        });
        await EnqueueQuorumAlertsAsync(incident.Id, elderProfileId, emergencyType, reason,
            incident.AlertCycleNumber, now, critical, ct);
        TouchCooldown(elderProfileId, rule, incident.Id, now, cooldown);
        if (saveChanges) await _db.SaveChangesAsync(ct);
        _logger.LogWarning("[CLINICAL-ALERT] Incident {IncidentId} for elder {ElderId}: {Reason}",
            incident.Id, elderProfileId, reason);
        return incident;
    }

    public async Task<Incident?> EvaluateSpO2SampleAsync(
        string elderProfileId, string deviceId, double spo2,
        DateTime measuredAtUtc, CancellationToken ct = default,
        TimeSpan? maxBackfillAge = null)
    {
        var now = DateTime.UtcNow;
        var measuredAt = measuredAtUtc.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(measuredAtUtc, DateTimeKind.Utc)
            : measuredAtUtc.ToUniversalTime();
        var backfillWindow = maxBackfillAge ?? TimeSpan.FromMinutes(2);
        // An old HealthKit backfill must never trigger a current notification.
        if (!double.IsFinite(spo2) || spo2 <= 0 || spo2 > 92 ||
            measuredAt < now - backfillWindow || measuredAt > now.AddMinutes(1)) return null;

        const string rule = "SPO2_LOW";
        var cooldown = await _db.ClinicalRuleCooldowns.FindAsync([elderProfileId, rule], ct);
        if (cooldown != null && now - cooldown.LastAlertAt < Cooldown) return null;

        var active = await _db.Incidents.FirstOrDefaultAsync(i => i.ElderProfileId == elderProfileId &&
            (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);
        var reason = $"SpO₂ ghi nhận {spo2:0.#}%. Hãy hỏi thăm, kiểm tra lại phép đo và liên hệ nhân viên y tế nếu mức thấp kéo dài hoặc có triệu chứng.";
        var homeAddress = await _db.ElderProfiles.Where(e => e.Id == elderProfileId)
            .Select(e => e.HomeAddress).FirstOrDefaultAsync(ct);
        var incident = active ?? new Incident
        {
            Id = Guid.NewGuid().ToString(), ElderProfileId = elderProfileId,
            TriggeredByDeviceId = deviceId, EmergencyType = EmergencyType.LowOxygen,
            Severity = IncidentSeverity.High, Status = IncidentStatus.Open,
            TriggeredAt = now, SpO2Percent = spo2, VitalsMeasuredAt = measuredAt,
            HomeAddressSnapshot = homeAddress,
            CreatedAt = now, UpdatedAt = now
        };
        if (active == null) _db.Incidents.Add(incident);
        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
            EventType = active == null ? "TRIGGERED" : "LOW_OXYGEN_READING",
            Description = reason, RecordedAt = now
        });

        var tokens = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == elderProfileId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive), ec => ec.CaregiverId,
                t => t.CaregiverId, (ec, t) => new { ec.CaregiverId, t.PushToken }).ToListAsync(ct);
        foreach (var token in tokens)
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
                RecipientCaregiverId = token.CaregiverId, PushToken = token.PushToken,
                Title = "SpO₂ thấp cần kiểm tra", Body = reason,
                DataPayloadJson = JsonSerializer.Serialize(new
                {
                    incidentId = incident.Id, elderProfileId, emergencyType = EmergencyType.LowOxygen,
                    priority = "HIGH", siren = false, alertCycleNumber = incident.AlertCycleNumber
                }),
                Status = "PENDING", RetryCount = 0, CreatedAt = now
            });
        TouchCooldown(elderProfileId, rule, incident.Id, now, cooldown);
        await _db.SaveChangesAsync(ct);
        return incident;
    }

    private async Task<bool> IsRestingAsync(string elderId, DateTime measuredAt, CancellationToken ct)
    {
        var steps = await _db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == elderId && m.MetricType == "STEPS" &&
                m.Timestamp >= measuredAt.AddMinutes(-5) && m.Timestamp <= measuredAt)
            .OrderBy(m => m.Timestamp).Select(m => m.Value).ToListAsync(ct);
        return steps.Count >= 2 && steps[0] >= 0 &&
            steps.Zip(steps.Skip(1), (before, after) => after >= before).All(x => x) &&
            steps[^1] - steps[0] <= 10;
    }

    private async Task<bool> HasSuddenRiseAsync(string elderId, DateTime measuredAt,
        double heartRate, CancellationToken ct)
    {
        var prior = await _db.HealthMeasurements.AsNoTracking()
            .Where(m => m.ElderProfileId == elderId && m.MetricType == "HEART_RATE" &&
                m.Timestamp >= measuredAt.AddMinutes(-5) && m.Timestamp < measuredAt &&
                m.Value > 0 && m.Value <= 300)
            .OrderBy(m => m.Value).Select(m => m.Value).ToListAsync(ct);
        if (prior.Count < 3) return false;
        var median = prior.Count % 2 == 1 ? prior[prior.Count / 2] :
            (prior[prior.Count / 2 - 1] + prior[prior.Count / 2]) / 2;
        return heartRate - median >= 15;
    }

    private void TouchCooldown(string elderId, string rule, string incidentId,
        DateTime now, ClinicalRuleCooldown? existing)
    {
        if (existing == null)
            _db.ClinicalRuleCooldowns.Add(new ClinicalRuleCooldown
            {
                ElderProfileId = elderId, RuleCode = rule,
                LastIncidentId = incidentId, LastAlertAt = now
            });
        else
        {
            existing.LastIncidentId = incidentId;
            existing.LastAlertAt = now;
        }
    }

    private async Task EnqueueQuorumAlertsAsync(string incidentId, string elderId,
        string emergencyType, string reason, int alertCycleNumber, DateTime now,
        bool critical, CancellationToken ct)
    {
        var tokens = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == elderId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive), ec => ec.CaregiverId,
                t => t.CaregiverId, (ec, t) => new { ec.CaregiverId, t.PushToken }).ToListAsync(ct);
        foreach (var token in tokens)
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incidentId, AlertCycleNumber = alertCycleNumber,
                RecipientCaregiverId = token.CaregiverId, PushToken = token.PushToken,
                Title = critical ? "CẢNH BÁO NHỊP TIM NGUY KỊCH" : "CẢNH BÁO NHỊP TIM", Body = reason,
                DataPayloadJson = JsonSerializer.Serialize(new
                {
                    incidentId, elderProfileId = elderId, emergencyType,
                    priority = critical ? "HIGH" : "NORMAL", siren = critical, alertCycleNumber
                }),
                Status = "PENDING", RetryCount = 0, CreatedAt = now
            });
    }
}
