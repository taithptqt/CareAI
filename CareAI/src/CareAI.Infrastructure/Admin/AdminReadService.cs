using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities.Admin;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using System.Linq.Expressions;
using CareAI.Core.Entities;
using CareAI.Infrastructure.Engines;

namespace CareAI.Infrastructure.Admin;

public sealed class AdminReadService(CareAiDbContext db)
{
    public async Task<AdminAuditDetail?> AuditDetailAsync(string id, CancellationToken ct)
    {
        var x = await db.Set<AdminAuditEvent>().AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
        return x is null ? null : new(x.Id, x.ActorId, x.Action, x.TargetId, x.Result, x.Reason, x.TraceId, Utc(x.OccurredAtUtc), x.ChangesJson);
    }
    private static DateTimeOffset Utc(DateTime value) => new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
    private static string MaskEmail(string email) => string.IsNullOrWhiteSpace(email) ? "Chưa có dữ liệu" : "••••@••••";
    private static string MaskPhone(string phone) => string.IsNullOrWhiteSpace(phone) ? "Chưa có dữ liệu" : "•••• ••• •••";

    public async Task<AdminListResponse<AdminAccountSummary>> AccountsAsync(string? search, bool locked, int page, int pageSize, CancellationToken ct, string? status = null)
    {
        var now = DateTime.UtcNow;
        var query = db.Caregivers.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(x => x.FullName.Contains(search) || x.Email.Contains(search));
        if (locked) query = query.Where(x => x.LockoutEnd > now);
        if (status == "Suspended") query = query.Where(x => db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == x.Id && s.IsSuspended));
        else if (status == "Active") query = query.Where(x => !db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == x.Id && s.IsSuspended));
        var count = await query.CountAsync(ct);
        page = Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / (double)pageSize)));
        var data = await query.OrderByDescending(x => x.CreatedAt).ThenBy(x => x.Id)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new { x.Id, x.FullName, x.Email, x.PhoneNumber, x.CreatedAt, x.LockoutEnd,
                Suspended = db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == x.Id && s.IsSuspended),
                Links = x.ElderCaregivers.Count(c => c.IsActive && !c.ElderProfile.IsDeleted) }).ToArrayAsync(ct);
        return new(data.Select(x => new AdminAccountSummary(x.Id, x.FullName, MaskEmail(x.Email), MaskPhone(x.PhoneNumber),
            Utc(x.CreatedAt), x.Suspended ? "Suspended" : "Active", x.LockoutEnd.HasValue ? Utc(x.LockoutEnd.Value) : null, x.Links)).ToArray(), count, page, pageSize, Utc(now));
    }

    public async Task<AdminAccountSummary?> AccountAsync(string id, CancellationToken ct)
    {
        var data = await db.Caregivers.AsNoTracking().Where(x => x.Id == id)
            .Select(x => new { x.Id, x.FullName, x.Email, x.PhoneNumber, x.CreatedAt, x.LockoutEnd,
                Suspended = db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == x.Id && s.IsSuspended),
                Links = x.ElderCaregivers.Count(c => c.IsActive && !c.ElderProfile.IsDeleted) }).SingleOrDefaultAsync(ct);
        return data is null ? null : new(data.Id, data.FullName, MaskEmail(data.Email), MaskPhone(data.PhoneNumber),
            Utc(data.CreatedAt), data.Suspended ? "Suspended" : "Active", data.LockoutEnd.HasValue ? Utc(data.LockoutEnd.Value) : null, data.Links);
    }

    public async Task<AdminListResponse<AdminDeviceSummary>> DevicesAsync(int page, int pageSize, CancellationToken ct, string? search = null, string? status = null)
    {
        var now = DateTime.UtcNow;
        var query = db.DeviceRegistrations.AsNoTracking().Where(d => !d.ElderProfile.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(d => d.Id.Contains(search) || (d.DeviceModel != null && d.DeviceModel.Contains(search)) || d.ElderProfile.FullName.Contains(search));
        if (status == "Offline") query = query.Where(OfflineAt(now));
        else if (status == "Revoked") query = query.Where(d => !d.IsActive);
        else if (status == "Unknown") query = query.Where(d => d.IsActive && (d.LastHeartbeat == default || d.LastHeartbeat > now));
        else if (status == "Online") query = query.Where(d => d.IsActive && d.LastHeartbeat != default && d.LastHeartbeat <= now
            && !db.DeviceRegistrations.Where(OfflineAt(now)).Any(o => o.Id == d.Id));
        var count = await query.CountAsync(ct);
        page = Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / (double)pageSize)));
        var rows = await query.OrderBy(x => x.LastHeartbeat).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new { x.Id, x.DeviceModel, x.DeviceType, ElderName = x.ElderProfile.FullName, x.IsActive, x.LastHeartbeat, x.WatchBatteryLevel }).ToArrayAsync(ct);
        return new(rows.Select(x => new AdminDeviceSummary(x.Id, x.DeviceModel ?? x.DeviceType, x.ElderName, x.IsActive,
            x.LastHeartbeat == default ? null : Utc(x.LastHeartbeat), !x.IsActive ? "Revoked" : x.LastHeartbeat == default || x.LastHeartbeat > now ? "Unknown" : x.LastHeartbeat < now.Subtract(DeviceStaleEngine.StaleAfterFor(x.DeviceType)) ? "Offline" : "Online",
            x.WatchBatteryLevel)).ToArray(), count, page, pageSize, Utc(now));
    }

    public async Task<AdminListResponse<AdminIncidentSummary>> IncidentsAsync(int page, int pageSize, CancellationToken ct,
        string? search = null, IncidentStatus? status = null, IncidentSeverity? severity = null, DateTime? from = null, DateTime? before = null)
    {
        var query = db.Incidents.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => x.ElderProfile.FullName.Contains(search) || x.EmergencyType.Contains(search) || x.Id.Contains(search));
        if (status is not null) query = query.Where(x => x.Status == status);
        if (severity is not null) query = query.Where(x => x.Severity == severity);
        if (from is not null) query = query.Where(x => x.TriggeredAt >= from);
        if (before is not null) query = query.Where(x => x.TriggeredAt < before);
        var now = DateTime.UtcNow;
        var count = await query.CountAsync(ct);
        page = Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / (double)pageSize)));
        var rows = await query.OrderByDescending(x => x.TriggeredAt).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize)
            .Select(x => new { x.Id, ElderName = x.ElderProfile.FullName, x.EmergencyType, x.Severity, x.Status, x.TriggeredAt }).ToArrayAsync(ct);
        return new(rows.Select(x => new AdminIncidentSummary(x.Id, x.ElderName, x.EmergencyType, x.Severity.ToString(), x.Status.ToString(), Utc(x.TriggeredAt))).ToArray(), count, page, pageSize, Utc(now));
    }

    public async Task<AdminOverviewResponse> OverviewAsync(CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        // Deliberately no clinical snapshots, GPS, contact data or arbitrary timeline descriptions.
        var incidents = await db.Incidents.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted && (x.Status == IncidentStatus.Open || x.Status == IncidentStatus.Acknowledged))
            .OrderBy(x => x.TriggeredAt).Select(x => new { x.Id, ElderName = x.ElderProfile.FullName, x.EmergencyType, x.Severity, x.Status, x.TriggeredAt }).Take(5).ToArrayAsync(ct);
        var offline = db.DeviceRegistrations.AsNoTracking().Where(OfflineAt(now));
        var devices = await offline.OrderBy(x => x.LastHeartbeat).Select(x => new { x.Id, x.DeviceModel, x.DeviceType, ElderName = x.ElderProfile.FullName, x.IsActive, x.LastHeartbeat, x.WatchBatteryLevel }).Take(5).ToArrayAsync(ct);
        return new(await db.Caregivers.CountAsync(ct), await db.ElderProfiles.CountAsync(x => !x.IsDeleted, ct),
            await db.DeviceRegistrations.CountAsync(x => !x.ElderProfile.IsDeleted && x.IsActive, ct),
            await db.Incidents.CountAsync(x => !x.ElderProfile.IsDeleted && (x.Status == IncidentStatus.Open || x.Status == IncidentStatus.Acknowledged), ct),
            await offline.CountAsync(ct), Utc(now),
            incidents.Select(x => new AdminIncidentSummary(x.Id, x.ElderName, x.EmergencyType, x.Severity.ToString(), x.Status.ToString(), Utc(x.TriggeredAt))).ToArray(),
            devices.Select(x => new AdminDeviceSummary(x.Id, x.DeviceModel ?? x.DeviceType, x.ElderName, x.IsActive, Utc(x.LastHeartbeat), "Offline", x.WatchBatteryLevel)).ToArray());
    }

    public async Task<AdminListResponse<AdminAuditSummary>> AuditAsync(int page, int pageSize, CancellationToken ct, string? search = null, string? result = null)
    {
        var now = DateTime.UtcNow;
        var since = now.AddDays(-7);
        var query = db.Set<AdminAuditEvent>().AsNoTracking().Where(x => x.OccurredAtUtc >= since);
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => x.ActorId.Contains(search) || x.Action.Contains(search) || x.TargetId.Contains(search) || x.TraceId.Contains(search));
        if (!string.IsNullOrWhiteSpace(result)) query = query.Where(x => x.Result == result);
        var count = await query.CountAsync(ct);
        page = Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / (double)pageSize)));
        var rows = await query.OrderByDescending(x => x.OccurredAtUtc).ThenBy(x => x.Id).Skip((page - 1) * pageSize).Take(pageSize).ToArrayAsync(ct);
        return new(rows.Select(x => new AdminAuditSummary(x.Id, x.ActorId, x.Action, x.TargetId, x.Result, x.TraceId, Utc(x.OccurredAtUtc))).ToArray(), count, page, pageSize, Utc(now));
    }

    private static Expression<Func<DeviceRegistration, bool>> OfflineAt(DateTime now)
    {
        var watch = now.Subtract(DeviceStaleEngine.AppleWatchStaleAfter);
        var phone = now.Subtract(DeviceStaleEngine.CompanionPhoneStaleAfter);
        var other = now.Subtract(DeviceStaleEngine.StaleAfter);
        return x => !x.ElderProfile.IsDeleted && x.IsActive && x.LastHeartbeat != default &&
            (x.DeviceType.ToLower() == "applewatch" ? x.LastHeartbeat < watch
                : x.DeviceType.ToLower() == "smartphone_companion" || x.DeviceType.ToLower() == "companionphone"
                    ? x.LastHeartbeat < phone : x.LastHeartbeat < other);
    }
}
