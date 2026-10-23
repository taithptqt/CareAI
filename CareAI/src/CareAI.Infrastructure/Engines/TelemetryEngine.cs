using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using CareAI.Core.Entities.Admin;

namespace CareAI.Infrastructure.Engines;

public class TelemetryEngine
{
    private readonly CareAiDbContext _db;
    private readonly ILogger<TelemetryEngine> _logger;

    public TelemetryEngine(CareAiDbContext db, ILogger<TelemetryEngine> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <summary>
    /// [BẤT BIẾN P0-3]: CHỈ COI LÀ DUPLICATE PACKET NẾU VI PHẠM TRÊN BẢNG ProcessedTelemetryLedgers!
    /// TUYỆT ĐỐI KHÔNG BẮT NHẦM LỖI TRÙNG LẶP TRÊN HealthMeasurements HAY BẢNG KHÁC.
    /// </summary>
    public static bool IsDuplicatePacketLedgerViolation(DbUpdateException ex)
    {
        var msg = ex.InnerException?.Message ?? ex.Message;
        if (msg.Contains("PK_ProcessedTelemetryLedgers", StringComparison.OrdinalIgnoreCase) ||
            msg.Contains("ProcessedTelemetryLedgers", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }
        return false;
    }

    /// <summary>
    /// Tiếp nhận gói tin cấp cứu Fast-Lane SOS / Fall Detection (< 50ms).
    /// </summary>
    public async Task<(bool Success, string? IncidentId, string Message)> ProcessFastLaneAsync(
        string deviceId,
        SosPacketRequest packet,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;

        // 1. Kiểm tra thiết bị
        var device = await _db.DeviceRegistrations
            .Include(d => d.ElderProfile)
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.IsActive, ct);

        if (device == null)
        {
            return (false, null, "Thiết bị không tồn tại hoặc đã bị thu hồi quyền.");
        }

        var elderId = device.ElderProfileId;
        var canonicalPacketId = string.IsNullOrWhiteSpace(packet.PacketId) 
            ? (packet.EventId != null ? $"FALL_{packet.EventId}" : $"SOS_{Guid.NewGuid():N}") 
            : packet.PacketId;

        // 2. Chống trùng lặp mức mạng (Idempotency Ledger)
        var existingLedger = await _db.ProcessedTelemetryLedgers
            .FindAsync(new object[] { deviceId, canonicalPacketId }, ct);

        if (existingLedger != null)
        {
            _logger.LogInformation("[FAST-LANE-DEDUP] Bỏ qua gói tin trùng lặp: Device={DeviceId}, PacketId={PacketId}", deviceId, canonicalPacketId);
            return (true, existingLedger.IncidentId, "Gói tin đã được tiếp nhận trước đó (Idempotent).");
        }

        // Cập nhật LastHeartbeat của thiết bị
        device.LastHeartbeat = now;
        device.UpdatedAt = now;

        var ledger = new ProcessedTelemetryLedger
        {
            DeviceId = deviceId,
            PacketId = canonicalPacketId,
            ReceivedAt = now
        };
        _db.ProcessedTelemetryLedgers.Add(ledger);

        // 3. [BẤT BIẾN FACT 35]: LƯU TOÀN BỘ MẪU ĐO SINH HIỆU ĐI KÈM TRONG GÓI TIN FAST-LANE
        if (packet.Samples != null && packet.Samples.Count > 0)
        {
            foreach (var sample in packet.Samples)
            {
                _db.HealthMeasurements.Add(new HealthMeasurement
                {
                    ElderProfileId = elderId,
                    DeviceId = deviceId,
                    PacketId = canonicalPacketId,
                    MetricType = sample.MetricType.ToUpperInvariant(),
                    Value = sample.Value,
                    Unit = sample.Unit ?? "EVENT",
                    Timestamp = sample.Timestamp == default ? now : sample.Timestamp,
                    RecordedAt = now
                });
            }
        }

        // 4. Quản lý Sự cố và bảo vệ Filtered Unique Index UIX_Incidents_SingleActiveElder
        var activeIncident = await _db.Incidents
            .FirstOrDefaultAsync(i => i.ElderProfileId == elderId && (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        string incidentId;
        if (activeIncident != null)
        {
            // Ghép nối vào sự cố hiện hữu, ghi timeline mà không tạo sự cố mới gây crash Unique Index
            incidentId = activeIncident.Id;
            activeIncident.UpdatedAt = now;
            if (!string.IsNullOrWhiteSpace(packet.GPSLocation) &&
                packet.TriggeredAt >= now.AddMinutes(-2))
            {
                activeIncident.CurrentGpsLocation = packet.GPSLocation.Trim();
                activeIncident.CurrentGpsMeasuredAt = packet.TriggeredAt;
                activeIncident.CurrentGpsIsSimulated = packet.GpsIsSimulated;
                activeIncident.CurrentGpsAccuracyMeters = packet.GpsAccuracyMeters;
            }

            // A fresh SOS/fall after ACK starts a new 60-second response round.
            if (activeIncident.Status == IncidentStatus.Acknowledged &&
                (!activeIncident.AcknowledgedAt.HasValue ||
                 !packet.TriggeredAt.HasValue || packet.TriggeredAt.Value > activeIncident.AcknowledgedAt.Value))
            {
                activeIncident.Status = IncidentStatus.Open;
                activeIncident.AlertCycleNumber++;
                activeIncident.AcknowledgedAt = null;
                activeIncident.AcknowledgedByCaregiverId = null;
                activeIncident.SlaBreachedAt = null;
                activeIncident.ReminderCount = 0;
                activeIncident.NextReminderAt = null;
                activeIncident.AlertStartedAt = now;
                activeIncident.AlertDeadlineAt = now.AddSeconds(60);
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = incidentId, AlertCycleNumber = activeIncident.AlertCycleNumber,
                    EventType = "EMERGENCY_REESCALATION",
                    Description = $"Nhận SOS/ngã mới sau ACK từ thiết bị {deviceId}.",
                    RecordedAt = now
                });
            }

            // Nếu sự cố hiện hữu chỉ là STALE_OFFLINE, lập tức leo thang thành cấp cứu khẩn cấp
            if (activeIncident.EmergencyType == EmergencyType.StaleOffline)
            {
                activeIncident.EmergencyType = packet.EmergencyType.ToUpperInvariant();
                activeIncident.Severity = Enum.TryParse<IncidentSeverity>(packet.Severity, true, out var s) ? s : IncidentSeverity.Critical;
                activeIncident.ConnectivityLostAt = null;
                CaptureSosSnapshot(activeIncident, packet, device.ElderProfile!, now);
                if (activeIncident.Severity == IncidentSeverity.Critical)
                {
                    activeIncident.AlertStartedAt = now;
                    activeIncident.AlertDeadlineAt = now.AddSeconds(60);
                }
            }
            else if (activeIncident.Status == IncidentStatus.Open &&
                     Enum.TryParse<IncidentSeverity>(packet.Severity, true, out var incomingSeverity) &&
                     incomingSeverity == IncidentSeverity.Critical &&
                     activeIncident.Severity != IncidentSeverity.Critical)
            {
                activeIncident.Severity = IncidentSeverity.Critical;
                activeIncident.AlertStartedAt = now;
                activeIncident.AlertDeadlineAt = now.AddSeconds(60);
                activeIncident.SlaBreachedAt = null;
                activeIncident.ReminderCount = 0;
                activeIncident.NextReminderAt = null;
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = incidentId, AlertCycleNumber = activeIncident.AlertCycleNumber,
                    EventType = "EMERGENCY_ESCALATION",
                    Description = $"Sự cố đang hoạt động leo thang Critical do tín hiệu {packet.EmergencyType}.",
                    RecordedAt = now
                });
            }

            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = incidentId,
                AlertCycleNumber = activeIncident.AlertCycleNumber,
                EventType = "REPEATED_EMERGENCY_SIGNAL",
                Description = $"Nhận thêm tín hiệu {packet.EmergencyType} từ thiết bị {deviceId}. Vị trí GPS: {packet.GPSLocation ?? "N/A"}",
                RecordedAt = now
            });
            _logger.LogWarning("[FAST-LANE] Cụ {ElderId} đang có sự cố {IncidentId}. Ghép nối tín hiệu mới vào timeline.", elderId, incidentId);
        }
        else
        {
            // Tạo mới sự cố Incident
            var newIncident = new Incident
            {
                Id = Guid.NewGuid().ToString(),
                ElderProfileId = elderId,
                TriggeredByDeviceId = deviceId,
                EmergencyType = packet.EmergencyType.ToUpperInvariant(),
                Severity = Enum.TryParse<IncidentSeverity>(packet.Severity, true, out var sev) ? sev : IncidentSeverity.Critical,
                Status = IncidentStatus.Open,
                TriggeredAt = packet.TriggeredAt ?? now,
                CreatedAt = now,
                UpdatedAt = now
            };

            CaptureSosSnapshot(newIncident, packet, device.ElderProfile!, now);
            if (newIncident.Severity == IncidentSeverity.Critical)
            {
                newIncident.AlertStartedAt = now;
                newIncident.AlertDeadlineAt = now.AddSeconds(60);
            }

            _db.Incidents.Add(newIncident);
            incidentId = newIncident.Id;

            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = incidentId,
                AlertCycleNumber = newIncident.AlertCycleNumber,
                EventType = "TRIGGERED",
                Description = $"Kích hoạt sự cố cấp cứu {packet.EmergencyType} từ thiết bị {deviceId}. Tọa độ GPS: {packet.GPSLocation ?? "N/A"}",
                RecordedAt = now
            });
        }

        // 5. [BẤT BIẾN FACT 34]: KÍCH HOẠT CÒI HÚ QUORUM ĐA NGƯỜI THÂN (CHỈ GỬI CHO CAREGIVER ĐANG ACTIVE)
        var activeCaregiverTokens = await _db.ElderCaregivers
            .Where(ec => ec.ElderProfileId == elderId && ec.IsActive
                && !_db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == ec.CaregiverId && s.IsSuspended))
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
                AlertCycleNumber = activeIncident?.AlertCycleNumber ?? 1,
                RecipientCaregiverId = item.CaregiverId,
                PushToken = item.PushToken,
                Title = "BÁO ĐỘNG CẤP CỨU KHẨN CẤP: NGƯỜI CAO TUỔI CẦN TRỢ GIÚP!",
                Body = $"Phát hiện {packet.EmergencyType} từ người cao tuổi {device.ElderProfile?.FullName ?? elderId}. Nhấn để mở còi hú cứu thương!",
                DataPayloadJson = System.Text.Json.JsonSerializer.Serialize(new
                {
                    incidentId,
                    elderProfileId = elderId,
                    emergencyType = packet.EmergencyType,
                    gpsLocation = packet.GPSLocation,
                    priority = "CRITICAL",
                    siren = true
                }),
                Status = "PENDING",
                RetryCount = 0,
                CreatedAt = now
            });
        }

        ledger.IncidentId = incidentId;
        try
        {
            await _db.SaveChangesAsync(ct);
            _logger.LogInformation("[FAST-LANE-SUCCESS] Xử lý thành công gói SOS cho Cụ {ElderId}. IncidentId={IncidentId}, OutboxTokens={Count}", elderId, incidentId, activeCaregiverTokens.Count);
            return (true, incidentId, "Sự cố cấp cứu đã được ghi nhận và đưa vào hàng đợi còi hú đa người thân thành công.");
        }
        catch (DbUpdateException ex) when (IsDuplicatePacketLedgerViolation(ex))
        {
            _logger.LogWarning("[FAST-LANE-RACE-DEDUP] Phát hiện va chạm trùng lặp ledger trong quá trình ghi CSDL. Trả về thành công Idempotent.");
            return (true, null, "Gói tin đã được tiếp nhận đồng thời trước đó.");
        }
    }

    private static void CaptureSosSnapshot(Incident incident, SosPacketRequest packet, ElderProfile elder, DateTime receivedAt)
    {
        var samples = packet.Samples ?? new List<HealthSampleDto>();

        HealthSampleDto? Latest(string metricType) => samples
            .Where(s => string.Equals(s.MetricType, metricType, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(s => s.Timestamp)
            .FirstOrDefault();

        var heartRate = Latest("HEART_RATE");
        var spo2 = Latest("SPO2");
        var systolic = Latest("BP_SYSTOLIC") ?? Latest("BLOOD_PRESSURE");
        var diastolic = Latest("BP_DIASTOLIC");

        incident.HeartRateBpm = heartRate?.Value;
        incident.SpO2Percent = spo2?.Value;
        incident.BpSystolic = systolic?.Value;
        incident.BpDiastolic = diastolic?.Value;
        var measuredAt = new[] { heartRate?.Timestamp, spo2?.Timestamp, systolic?.Timestamp, diastolic?.Timestamp }
            .Where(t => t.HasValue && t.Value != default)
            .Max();
        incident.VitalsMeasuredAt = measuredAt ?? (samples.Count > 0 ? receivedAt : null);
        incident.GpsLocation = string.IsNullOrWhiteSpace(packet.GPSLocation) ? null : packet.GPSLocation.Trim();
        incident.CurrentGpsLocation = incident.GpsLocation;
        incident.CurrentGpsMeasuredAt = incident.GpsLocation == null ? null : packet.TriggeredAt ?? receivedAt;
        incident.CurrentGpsIsSimulated = incident.GpsLocation == null ? null : packet.GpsIsSimulated;
        incident.CurrentGpsAccuracyMeters = incident.GpsLocation == null ? null : packet.GpsAccuracyMeters;
        incident.HomeAddressSnapshot = elder.HomeAddress;
    }

    /// <summary>
    /// Tiếp nhận gói tin viễn trắc định kỳ theo mẻ Batch-Lane (15 phút).
    /// </summary>
    public async Task<(int ProcessedCount, string Message)> ProcessBatchLaneAsync(
        string deviceId,
        TelemetryBatchRequest batch,
        CancellationToken ct = default,
        List<HealthMeasurement>? acceptedSamples = null)
    {
        var now = DateTime.UtcNow;

        var device = await _db.DeviceRegistrations
            .FirstOrDefaultAsync(d => d.Id == deviceId && d.IsActive, ct);

        if (device == null)
        {
            return (0, "Thiết bị không tồn tại hoặc đã bị thu hồi.");
        }

        var elderId = device.ElderProfileId;
        device.LastHeartbeat = now;
        device.UpdatedAt = now;

        int addedCount = 0;
        var seenSamples = new HashSet<(string DeviceId, string MetricType, DateTime Timestamp)>();
        foreach (var sample in batch.Samples)
        {
            var timestamp = sample.Timestamp == default ? now : sample.Timestamp;
            var metricType = sample.MetricType.ToUpperInvariant();
            if (!seenSamples.Add((deviceId, metricType, timestamp))) continue;

            // Kiểm tra trùng lặp trên bộ nhớ đệm hoặc DB
            var exists = await _db.HealthMeasurements.AnyAsync(m =>
                m.ElderProfileId == elderId &&
                m.DeviceId == deviceId &&
                m.Timestamp == timestamp &&
                m.MetricType == metricType, ct);

            if (!exists)
            {
                var measurement = new HealthMeasurement
                {
                    ElderProfileId = elderId,
                    DeviceId = deviceId,
                    PacketId = batch.BatchId,
                    MetricType = metricType,
                    Value = sample.Value,
                    Unit = sample.Unit ?? (metricType == "HEART_RATE" ? "bpm" : "unit"),
                    Timestamp = timestamp,
                    RecordedAt = now
                };
                _db.HealthMeasurements.Add(measurement);
                acceptedSamples?.Add(measurement);
                addedCount++;
            }
        }

        await _db.SaveChangesAsync(ct);
        return (addedCount, $"Đã lưu {addedCount} mẫu đo viễn trắc mới vào CSDL.");
    }
}
