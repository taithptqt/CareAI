using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using CareAI.Core.DTOs;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

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
            return (true, null, "Gói tin đã được tiếp nhận trước đó (Idempotent).");
        }

        // Cập nhật LastHeartbeat của thiết bị
        device.LastHeartbeat = now;
        device.UpdatedAt = now;

        _db.ProcessedTelemetryLedgers.Add(new ProcessedTelemetryLedger
        {
            DeviceId = deviceId,
            PacketId = canonicalPacketId,
            ReceivedAt = now
        });

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

            // Nếu sự cố hiện hữu chỉ là STALE_OFFLINE, lập tức leo thang thành cấp cứu khẩn cấp
            if (activeIncident.EmergencyType == EmergencyType.StaleOffline)
            {
                activeIncident.EmergencyType = packet.EmergencyType.ToUpperInvariant();
                activeIncident.Severity = Enum.TryParse<IncidentSeverity>(packet.Severity, true, out var s) ? s : IncidentSeverity.Critical;
            }

            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = incidentId,
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

            _db.Incidents.Add(newIncident);
            incidentId = newIncident.Id;

            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = incidentId,
                EventType = "TRIGGERED",
                Description = $"Kích hoạt sự cố cấp cứu {packet.EmergencyType} từ thiết bị {deviceId}. Tọa độ GPS: {packet.GPSLocation ?? "N/A"}",
                RecordedAt = now
            });
        }

        // 5. [BẤT BIẾN FACT 34]: KÍCH HOẠT CÒI HÚ QUORUM ĐA NGƯỜI THÂN (CHỈ GỬI CHO CAREGIVER ĐANG ACTIVE)
        var activeCaregiverTokens = await _db.ElderCaregivers
            .Where(ec => ec.ElderProfileId == elderId && ec.IsActive)
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

    /// <summary>
    /// Tiếp nhận gói tin viễn trắc định kỳ theo mẻ Batch-Lane (15 phút).
    /// </summary>
    public async Task<(int ProcessedCount, string Message)> ProcessBatchLaneAsync(
        string deviceId,
        TelemetryBatchRequest batch,
        CancellationToken ct = default)
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
        foreach (var sample in batch.Samples)
        {
            var timestamp = sample.Timestamp == default ? now : sample.Timestamp;
            var metricType = sample.MetricType.ToUpperInvariant();

            // Kiểm tra trùng lặp trên bộ nhớ đệm hoặc DB
            var exists = await _db.HealthMeasurements.AnyAsync(m =>
                m.ElderProfileId == elderId &&
                m.DeviceId == deviceId &&
                m.Timestamp == timestamp &&
                m.MetricType == metricType, ct);

            if (!exists)
            {
                _db.HealthMeasurements.Add(new HealthMeasurement
                {
                    ElderProfileId = elderId,
                    DeviceId = deviceId,
                    PacketId = batch.BatchId,
                    MetricType = metricType,
                    Value = sample.Value,
                    Unit = sample.Unit ?? (metricType == "HEART_RATE" ? "bpm" : "unit"),
                    Timestamp = timestamp,
                    RecordedAt = now
                });
                addedCount++;
            }
        }

        await _db.SaveChangesAsync(ct);
        return (addedCount, $"Đã lưu {addedCount} mẫu đo viễn trắc mới vào CSDL.");
    }
}
