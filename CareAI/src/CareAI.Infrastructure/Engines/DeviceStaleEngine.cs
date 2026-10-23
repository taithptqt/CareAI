using CareAI.Core.Entities.Admin;
using System.Text.Json;
using CareAI.Core.Entities;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.Engines;

public class DeviceStaleEngine
{
    public static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(5);
    public static readonly TimeSpan AppleWatchStaleAfter = TimeSpan.FromHours(3);
    public static readonly TimeSpan CompanionPhoneStaleAfter = TimeSpan.FromMinutes(25);

    public static TimeSpan StaleAfterFor(string? deviceType)
    {
        if (string.Equals(deviceType, "AppleWatch", StringComparison.OrdinalIgnoreCase))
            return AppleWatchStaleAfter;
        if (string.Equals(deviceType, "SMARTPHONE_COMPANION", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(deviceType, "CompanionPhone", StringComparison.OrdinalIgnoreCase))
            return CompanionPhoneStaleAfter;
        return StaleAfter;
    }
    private readonly CareAiDbContext _db;
    private readonly ILogger<DeviceStaleEngine> _logger;

    public DeviceStaleEngine(CareAiDbContext db, ILogger<DeviceStaleEngine> logger)
    {
        _db = db;
        _logger = logger;
    }

    public async Task ScanAsync(DateTime nowUtc, CancellationToken ct = default)
    {
        if (nowUtc.Kind != DateTimeKind.Utc)
            throw new ArgumentException("Scan time must be UTC.", nameof(nowUtc));

        var elderIds = await _db.DeviceRegistrations.AsNoTracking()
            .Where(d => d.IsActive).Select(d => d.ElderProfileId).Distinct().ToListAsync(ct);
        foreach (var elderId in elderIds)
        {
            try
            {
                await ScanElderAsync(elderId, nowUtc, ct);
            }
            catch (DbUpdateConcurrencyException)
            {
                // Another request changed the incident after this scan read its RowVersion.
                // The next scan will observe the committed state.
                _db.ChangeTracker.Clear();
                _logger.LogInformation("[WATCHDOG-RACE] Incident changed for elder {ElderId}.", elderId);
            }
            catch (DbUpdateException ex) when (IsActiveIncidentConflict(ex))
            {
                // SOS/clinical processing won the filtered unique active-incident index.
                _db.ChangeTracker.Clear();
                _logger.LogInformation("[WATCHDOG-RACE] Active incident already exists for elder {ElderId}.", elderId);
            }
        }
    }

    private async Task ScanElderAsync(string elderId, DateTime now, CancellationToken ct)
    {
        var devices = await _db.DeviceRegistrations.AsNoTracking()
            .Where(d => d.ElderProfileId == elderId && d.IsActive)
            .Select(d => new { d.Id, d.DeviceType, d.LastHeartbeat }).ToListAsync(ct);
        if (devices.Count == 0) return;

        var allStale = devices.All(d => d.LastHeartbeat < now.Subtract(StaleAfterFor(d.DeviceType)));
        var active = await _db.Incidents.FirstOrDefaultAsync(i => i.ElderProfileId == elderId &&
            (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

        if (allStale)
        {
            var maxTimeoutMinutes = (int)devices.Max(d => StaleAfterFor(d.DeviceType)).TotalMinutes;
            if (active == null)
            {
                var elder = await _db.ElderProfiles.AsNoTracking()
                    .Where(e => e.Id == elderId)
                    .Select(e => new { e.FullName, e.HomeAddress }).FirstAsync(ct);
                var incident = new Incident
                {
                    Id = Guid.NewGuid().ToString(), ElderProfileId = elderId,
                    TriggeredByDeviceId = devices[0].Id,
                    EmergencyType = EmergencyType.StaleOffline,
                    Severity = IncidentSeverity.Medium, Status = IncidentStatus.Open,
                    TriggeredAt = now, CreatedAt = now, UpdatedAt = now,
                    ConnectivityLostAt = now, HomeAddressSnapshot = elder.HomeAddress
                };
                _db.Incidents.Add(incident);
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
                    EventType = "TRIGGERED",
                    Description = $"Tất cả {devices.Count} thiết bị của {elder.FullName} mất tín hiệu quá {maxTimeoutMinutes} phút.",
                    RecordedAt = now
                });
                await QueueOutboxAsync(incident, "DEVICE_OFFLINE",
                    "Thiết bị mất kết nối", $"Tất cả thiết bị của người cao tuổi đã mất tín hiệu quá {maxTimeoutMinutes} phút.", now, ct);
                await _db.SaveChangesAsync(ct);
                _logger.LogWarning("[WATCHDOG-ALERT] All devices offline for elder {ElderId}.", elderId);
                return;
            }

            // One active incident per elder: attach connectivity evidence to the current incident.
            if (active.ConnectivityLostAt.HasValue) return;
            active.ConnectivityLostAt = now;
            active.UpdatedAt = now;
            var emergency = active.EmergencyType is EmergencyType.Fall or EmergencyType.ManualSos;
            _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
            {
                IncidentId = active.Id, AlertCycleNumber = active.AlertCycleNumber,
                EventType = emergency ? "DEVICE_STALE_SUPPRESSED" : "DEVICE_STALE",
                Description = $"Tất cả {devices.Count} thiết bị mất tín hiệu quá {maxTimeoutMinutes} phút; ghi vào sự cố {active.EmergencyType} hiện tại.",
                RecordedAt = now
            });
            await _db.SaveChangesAsync(ct);
            return;
        }

        await TryAutoResolveStaleIncidentAsync(elderId, now, ct);
    }

    /// <summary>
    /// Tự động đóng (Auto-resolve) sự cố STALE_OFFLINE khi thiết bị gửi lại tín hiệu (telemetry/heartbeat/sync) (Hướng 3).
    /// </summary>
    public async Task<bool> TryAutoResolveStaleIncidentAsync(string elderId, DateTime now, CancellationToken ct = default)
    {
        try
        {
            var active = await _db.Incidents.FirstOrDefaultAsync(i => i.ElderProfileId == elderId &&
                (i.Status == IncidentStatus.Open || i.Status == IncidentStatus.Acknowledged), ct);

            if (active == null) return false;

            if (active.EmergencyType == EmergencyType.StaleOffline)
            {
                active.Status = IncidentStatus.Resolved;
                active.ResolvedAt = now;
                active.ResolutionNotes = "Hệ thống tự động đóng: Ít nhất một thiết bị đã kết nối lại.";
                active.ConnectivityLostAt = null;
                active.UpdatedAt = now;
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = active.Id, AlertCycleNumber = active.AlertCycleNumber,
                    EventType = "AUTO_RESOLVED", Description = active.ResolutionNotes,
                    RecordedAt = now
                });
                await QueueOutboxAsync(active, "DEVICE_RECONNECTED",
                    "Thiết bị đã kết nối lại", active.ResolutionNotes, now, ct);
                await _db.SaveChangesAsync(ct);
                _logger.LogInformation("[DEVICE-RECONNECT-AUTO-RESOLVED] STALE_OFFLINE incident {IncidentId} auto-resolved for elder {ElderId}.", active.Id, elderId);
                return true;
            }
            else if (active.ConnectivityLostAt.HasValue)
            {
                active.ConnectivityLostAt = null;
                active.UpdatedAt = now;
                _db.IncidentTimelineEvents.Add(new IncidentTimelineEvent
                {
                    IncidentId = active.Id, AlertCycleNumber = active.AlertCycleNumber,
                    EventType = "DEVICE_RECONNECTED",
                    Description = "Ít nhất một thiết bị đã gửi tín hiệu trở lại.", RecordedAt = now
                });
                await _db.SaveChangesAsync(ct);
                return false;
            }

            return false;
        }
        catch (DbUpdateConcurrencyException)
        {
            _db.ChangeTracker.Clear();
            _logger.LogInformation("[DEVICE-RECONNECT-RACE] Incident changed during auto-resolve for elder {ElderId}.", elderId);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[DEVICE-RECONNECT-ERROR] Failed to auto-resolve stale incident for elder {ElderId}.", elderId);
            return false;
        }
    }

    private async Task QueueOutboxAsync(Incident incident, string eventType,
        string title, string body, DateTime now, CancellationToken ct)
    {
        var recipients = await _db.ElderCaregivers.Where(ec => ec.ElderProfileId == incident.ElderProfileId && ec.IsActive && !_db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == ec.CaregiverId && s.IsSuspended))
            .Join(_db.CaregiverPushTokens.Where(t => t.IsActive), ec => ec.CaregiverId,
                t => t.CaregiverId, (ec, t) => new { ec.CaregiverId, t.PushToken }).ToListAsync(ct);
        foreach (var recipient in recipients)
            _db.NotificationOutboxes.Add(new NotificationOutbox
            {
                IncidentId = incident.Id, AlertCycleNumber = incident.AlertCycleNumber,
                RecipientCaregiverId = recipient.CaregiverId, PushToken = recipient.PushToken,
                Title = title, Body = body,
                DataPayloadJson = JsonSerializer.Serialize(new
                {
                    incidentId = incident.Id, elderProfileId = incident.ElderProfileId,
                    eventType, siren = false, priority = "NORMAL"
                }),
                Status = "PENDING", RetryCount = 0, CreatedAt = now
            });
    }

    private static bool IsActiveIncidentConflict(DbUpdateException ex) =>
        ex.InnerException is SqlException sql &&
        sql.Errors.Cast<SqlError>().Any(error => error.Number is 2601 or 2627) &&
        sql.Message.Contains("UIX_Incidents_SingleActiveElder", StringComparison.OrdinalIgnoreCase);
}
