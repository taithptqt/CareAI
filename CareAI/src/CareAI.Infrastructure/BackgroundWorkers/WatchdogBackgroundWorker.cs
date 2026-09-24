using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;

namespace CareAI.Infrastructure.BackgroundWorkers;

public class WatchdogBackgroundWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<WatchdogBackgroundWorker> _logger;

    public WatchdogBackgroundWorker(IServiceScopeFactory scopeFactory, ILogger<WatchdogBackgroundWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[WATCHDOG-WORKER] Khởi động Background Worker giám sát thiết bị rớt mạng định kỳ 60 giây...");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CheckStaleDevicesAsync(stoppingToken);
                await ResolveReconnectedDevicesAsync(stoppingToken);
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                _logger.LogError(ex, "[WATCHDOG-ERROR] Lỗi trong chu kỳ quét Watchdog: {Message}", ex.Message);
            }

            await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
        }
    }

    private async Task CheckStaleDevicesAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var now = DateTime.UtcNow;
        var staleCutoff = now.AddMinutes(-15); // Ngưỡng mất tín hiệu 15 phút

        var activeElders = await db.ElderProfiles
            .Include(e => e.Devices)
            .Where(e => e.Devices.Any(d => d.IsActive))
            .ToListAsync(ct);

        foreach (var elder in activeElders)
        {
            var activeDevices = elder.Devices.Where(d => d.IsActive).ToList();
            if (activeDevices.Count == 0) continue;

            // Kiểm tra: TẤT CẢ các thiết bị của cụ đều không có heartbeat trong 15 phút
            var maxHeartbeat = activeDevices.Max(d => d.LastHeartbeat);
            if (maxHeartbeat < staleCutoff)
            {
                // BẤT BIẾN ỨC CHẾ: Nếu đang có cấp cứu Fall hoặc SOS thì không tạo sự cố mất mạng đè lên
                var hasActiveEmergency = await db.Incidents.AnyAsync(i =>
                    i.ElderProfileId == elder.Id &&
                    (i.EmergencyType == EmergencyType.Fall || i.EmergencyType == EmergencyType.ManualSos) &&
                    (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

                if (hasActiveEmergency)
                {
                    _logger.LogInformation("[WATCHDOG-SUPPRESS] Cụ {ElderId} đang có cấp cứu khẩn cấp. Ức chế tạo sự cố mất mạng rác.", elder.Id);
                    continue;
                }

                // Kiểm tra xem đã có sự cố STALE_OFFLINE nào đang mở chưa
                var hasStaleIncident = await db.Incidents.AnyAsync(i =>
                    i.ElderProfileId == elder.Id &&
                    i.EmergencyType == EmergencyType.StaleOffline &&
                    (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

                if (!hasStaleIncident)
                {
                    var staleIncident = new Incident
                    {
                        Id = Guid.NewGuid().ToString(),
                        ElderProfileId = elder.Id,
                        TriggeredByDeviceId = activeDevices.First().Id,
                        EmergencyType = EmergencyType.StaleOffline,
                        Severity = IncidentSeverity.Medium,
                        Status = IncidentStatus.Open,
                        TriggeredAt = now,
                        CreatedAt = now,
                        UpdatedAt = now
                    };

                    db.Incidents.Add(staleIncident);
                    db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                    {
                        IncidentId = staleIncident.Id,
                        EventType = "TRIGGERED",
                        Description = $"Toàn bộ thiết bị của người cao tuổi {elder.FullName} đã mất kết nối quá 15 phút.",
                        RecordedAt = now
                    });

                    _logger.LogWarning("[WATCHDOG-ALERT] Tạo sự cố STALE_OFFLINE cho Cụ {ElderId}.", elder.Id);
                }
            }
        }

        await db.SaveChangesAsync(ct);
    }

    private async Task ResolveReconnectedDevicesAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var now = DateTime.UtcNow;
        var staleCutoff = now.AddMinutes(-15);

        // Tự động đóng các sự cố mất mạng khi thiết bị có tín hiệu trở lại
        var openStaleIncidents = await db.Incidents
            .Include(i => i.ElderProfile)
                .ThenInclude(e => e.Devices)
            .Where(i => i.EmergencyType == EmergencyType.StaleOffline && 
                       (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged))
            .ToListAsync(ct);

        foreach (var incident in openStaleIncidents)
        {
            var latestHeartbeat = incident.ElderProfile.Devices
                .Where(d => d.IsActive)
                .Select(d => (DateTime?)d.LastHeartbeat)
                .Max();

            if (latestHeartbeat.HasValue && latestHeartbeat.Value >= staleCutoff)
            {
                incident.Status = IncidentStatus.Resolved;
                incident.ResolvedAt = now;
                incident.ResolutionNotes = "Hệ thống tự động đóng: Thiết bị đã kết nối và gửi tín hiệu trở lại bình thường.";
                incident.UpdatedAt = now;

                db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = incident.Id,
                    EventType = "AUTO_RESOLVED",
                    Description = "Thiết bị khôi phục kết nối thành công.",
                    RecordedAt = now
                });

                _logger.LogInformation("[WATCHDOG-RECOVER] Tự động đóng sự cố mất mạng cho Cụ {ElderId}.", incident.ElderProfileId);
            }
        }

        await db.SaveChangesAsync(ct);
    }
}
