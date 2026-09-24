using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

namespace CareAI.Infrastructure.Engines;

public class ClinicalDiagnosticEngine
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<ClinicalDiagnosticEngine> _logger;

    public ClinicalDiagnosticEngine(CareAiDbContext db, ILogger<ClinicalDiagnosticEngine> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// Thẩm định luật lâm sàng đối với từng mẫu đo nhịp tim mới nạp.
    /// </summary>
    public async Task<Incident?> EvaluateHeartRateSampleAsync(
        string elderProfileId,
        string deviceId,
        double heartRate,
        int recentSteps = 0,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;

        // 1. Phân loại mức độ vi phạm quy tắc lâm sàng
        string? emergencyType = null;
        IncidentSeverity severity = IncidentSeverity.Low;
        string clinicalReason = string.Empty;

        if (heartRate >= 180)
        {
            emergencyType = EmergencyType.Tachycardia;
            severity = IncidentSeverity.Critical;
            clinicalReason = $"CẢNH BÁO NGUY KỊCH: Nhịp tim đạt {heartRate} bpm (nguy cơ rung thất / nhịp nhanh thất kịch phát)!";
        }
        else if (heartRate <= 35)
        {
            emergencyType = EmergencyType.Bradycardia;
            severity = IncidentSeverity.Critical;
            clinicalReason = $"CẢNH BÁO NGUY KỊCH: Nhịp tim tụt xuống {heartRate} bpm (nguy cơ vô tâm thu / ngừng tuần hoàn)!";
        }
        else if (heartRate > 120 && recentSteps <= 10)
        {
            emergencyType = EmergencyType.Tachycardia;
            severity = IncidentSeverity.High;
            clinicalReason = $"Cảnh báo: Nhịp tim tăng cao {heartRate} bpm trong trạng thái nghỉ ngơi.";
        }
        else if (heartRate < 40)
        {
            emergencyType = EmergencyType.Bradycardia;
            severity = IncidentSeverity.High;
            clinicalReason = $"Cảnh báo: Nhịp tim chậm kéo dài {heartRate} bpm.";
        }

        if (emergencyType == null)
        {
            // Nhịp tim an toàn
            return null;
        }

        // 2. Kiểm tra sự cố hiện hữu để bảo vệ Filtered Unique Index UIX_Incidents_SingleActiveElder
        var activeIncident = await _db.Incidents
            .FirstOrDefaultAsync(i => i.ElderProfileId == elderProfileId && 
                                     (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        if (activeIncident != null)
        {
            // Leo thang lâm sàng: Nếu đang Warning mà chuyển thành Critical -> Nâng mức nghiêm trọng
            if (severity == IncidentSeverity.Critical && activeIncident.Severity != IncidentSeverity.Critical)
            {
                activeIncident.Severity = IncidentSeverity.Critical;
                activeIncident.Status = IncidentStatus.Open; // Mở lại để yêu cầu chú ý khẩn
                activeIncident.UpdatedAt = now;

                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = activeIncident.Id,
                    EventType = "CLINICAL_ESCALATION",
                    Description = $"LEO THANG LÂM SÀNG NGUY KỊCH: {clinicalReason}",
                    RecordedAt = now
                });

                // Đẩy thông báo còi hú leo thang
                await EnqueueQuorumAlertsAsync(activeIncident.Id, elderProfileId, emergencyType, clinicalReason, now, ct);
                await _db.SaveChangesAsync(ct);
                return activeIncident;
            }

            // Ghi nhật ký timeline mà không tạo sự cố mới
            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = activeIncident.Id,
                EventType = "CLINICAL_FOLLOWUP",
                Description = $"Ghi nhận chỉ số nhịp tim bất thường liên tục: {heartRate} bpm. Lý do: {clinicalReason}",
                RecordedAt = now
            });
            await _db.SaveChangesAsync(ct);
            return activeIncident;
        }

        // 3. Khởi tạo Incident lâm sàng mới
        var incident = new Incident
        {
            Id = Guid.NewGuid().ToString(),
            ElderProfileId = elderProfileId,
            TriggeredByDeviceId = deviceId,
            EmergencyType = emergencyType,
            Severity = severity,
            Status = IncidentStatus.Open,
            TriggeredAt = now,
            CreatedAt = now,
            UpdatedAt = now
        };

        _db.Incidents.Add(incident);

        _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
        {
            IncidentId = incident.Id,
            EventType = "TRIGGERED",
            Description = clinicalReason,
            RecordedAt = now
        });

        // 4. Kích hoạt còi hú Quorum
        await EnqueueQuorumAlertsAsync(incident.Id, elderProfileId, emergencyType, clinicalReason, now, ct);

        await _db.SaveChangesAsync(ct);
        _logger.LogWarning("[CLINICAL-ALERT] Đã tạo sự cố lâm sàng {IncidentId} cho Cụ {ElderId}. Lý do: {Reason}", incident.Id, elderProfileId, clinicalReason);
        return incident;
    }

    private async Task EnqueueQuorumAlertsAsync(
        string incidentId,
        string elderProfileId,
        string emergencyType,
        string reason,
        DateTime now,
        CancellationToken ct)
    {
        var activeCaregiverTokens = await _db.ElderCaregivers
            .Where(ec => ec.ElderProfileId == elderProfileId && ec.IsActive)
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive),
                ec => ec.CaregiverId,
                t => t.CaregiverId,
                (ec, t) => new { ec.CaregiverId, t.PushToken })
            .ToListAsync(ct);

        foreach (var item in activeCaregiverTokens)
        {
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incidentId,
                RecipientCaregiverId = item.CaregiverId,
                PushToken = item.PushToken,
                Title = "CẢNH BÁO LÂM SÀNG BẤT THƯỜNG: TIM MẠCH NGUY HIỂM!",
                Body = reason,
                DataPayloadJson = System.Text.Json.JsonSerializer.Serialize(new
                {
                    incidentId,
                    elderProfileId,
                    emergencyType,
                    priority = "HIGH",
                    siren = true
                }),
                Status = "PENDING",
                RetryCount = 0,
                CreatedAt = now
            });
        }
    }
}
