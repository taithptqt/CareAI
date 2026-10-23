using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public sealed class AdminOperationsReadService(CareAiDbContext db, AdminCommandOptions options)
{
    public static string Version(object value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonSerializer.Serialize(value))));
    public static string AccountVersion(Caregiver x, CaregiverAdminState? state = null) => Version(new { x.FullName, x.PhoneNumber, x.LockoutEnd, x.FailedLoginAttempts, Suspended = state?.IsSuspended ?? false, SecurityVersion = state?.SecurityVersion ?? 0 });
    public static string DeviceVersion(DeviceRegistration x) => Version(new { x.IsActive, x.ElderProfileId, x.DeviceModel });
    public static string LinkVersion(ElderCaregiver x) => Version(new { x.IsActive, x.Role, x.ElderProfileId, x.CaregiverId });
    public static string LinkGroupVersion(IEnumerable<ElderCaregiver> group) => Version(group.OrderBy(x => x.Id).Select(x => new { x.Id, x.IsActive, x.Role, x.CaregiverId }).ToArray());
    private static DateTimeOffset Utc(DateTime x) => new(DateTime.SpecifyKind(x, DateTimeKind.Utc));
    private static string Time(DateTime? x) => x.HasValue ? Utc(x.Value).ToOffset(TimeSpan.FromHours(7)).ToString("dd/MM/yyyy HH:mm") : "Chưa có dữ liệu";

    public async Task<AdminListResponse<AdminRecord>> ListAsync(string kind, string? search, int page, CancellationToken ct)
    {
        const int size = 25;
        var count = 0;
        IReadOnlyList<AdminRecord> rows;
        switch (kind)
        {
            case "staff":
                var staff = db.Set<AdminUser>().AsNoTracking();
                if (!string.IsNullOrWhiteSpace(search)) staff = staff.Where(x => x.FullName.Contains(search) || x.NormalizedEmail.Contains(search));
                count = await staff.CountAsync(ct); page = Clamp(page, count);
                var users = await staff.OrderBy(x => x.FullName).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size).ToArrayAsync(ct);
                rows = users.Select(x => new AdminRecord(x.Id, x.FullName, x.NormalizedEmail, x.IsActive ? "Hoạt động" : "Tạm ngưng", Convert.ToBase64String(x.RowVersion),
                    [new("Vai trò", x.Role), new("Đăng nhập gần nhất", Time(x.LastLoginAtUtc)), new("MFA", x.MfaEnabled ? "Đã bật TOTP" : "Chưa thiết lập"), new("Phiên bản quyền", x.SecurityVersion.ToString())])).ToArray();
                break;
            case "elders":
                var elders = db.ElderProfiles.AsNoTracking().Where(x => !x.IsDeleted);
                if (!string.IsNullOrWhiteSpace(search)) elders = elders.Where(x => x.FullName.Contains(search));
                count = await elders.CountAsync(ct); page = Clamp(page, count);
                var profiles = await elders.OrderBy(x => x.FullName).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size)
                    .Select(x => new { x.Id, x.FullName, x.DateOfBirth, Links = x.ElderCaregivers.Count(l => l.IsActive), Devices = x.Devices.Count(d => d.IsActive), Last = x.Devices.Where(d => d.IsActive).Max(d => (DateTime?)d.LastHeartbeat) }).ToArrayAsync(ct);
                rows = profiles.Select(x => new AdminRecord(x.Id, x.FullName, "Hồ sơ người cao tuổi", "Đang quản lý", "read-only",
                    [new("Năm sinh", x.DateOfBirth.Year.ToString()), new("Người thân", x.Links.ToString()), new("Thiết bị còn hiệu lực", x.Devices.ToString()), new("Heartbeat gần nhất", Time(x.Last))])).ToArray();
                break;
            case "care-links":
                var links = db.ElderCaregivers.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted);
                if (!string.IsNullOrWhiteSpace(search)) links = links.Where(x => x.Caregiver.FullName.Contains(search) || x.ElderProfile.FullName.Contains(search));
                count = await links.CountAsync(ct); page = Clamp(page, count);
                var relations = await links.OrderBy(x => x.ElderProfile.FullName).ThenBy(x => x.Id).Skip((page - 1) * size).Take(size)
                    .Select(x => new { Link = x, ElderName = x.ElderProfile.FullName, Name = x.Caregiver.FullName }).ToArrayAsync(ct);
                rows = relations.Select(x => new AdminRecord(x.Link.Id, x.ElderName, x.Name, x.Link.IsActive ? "Đang liên kết" : "Đã ngừng", LinkVersion(x.Link),
                    [new("Vai trò", x.Link.Role.ToString()), new("ID hồ sơ", x.Link.ElderProfileId), new("ID người thân", x.Link.CaregiverId), new("Ngày liên kết", Time(x.Link.AssignedAt))])).ToArray();
                break;
            default: throw new ArgumentException("Unknown module.");
        }
        return new(rows, count, page, size, DateTimeOffset.UtcNow);
    }

    public async Task<AdminRecord?> AccountAsync(string id, CancellationToken ct)
    {
        var x = await db.Caregivers.AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
        var state = await db.Set<CaregiverAdminState>().AsNoTracking().SingleOrDefaultAsync(x => x.CaregiverId == id, ct);
        return x is null ? null : new(x.Id, x.FullName, "Thông tin tài khoản", state?.IsSuspended == true ? "Tạm ngưng" : "Hoạt động", AccountVersion(x, state),
            [new("Họ tên", x.FullName), new("Số điện thoại", x.PhoneNumber), new("Email", "Đã che theo quyền đọc"), new("Khóa đăng nhập đến", Time(x.LockoutEnd)),
             new("API thực thi phiên", options.CaregiverApiEnforcementReady ? "true" : "false")]);
    }

    public async Task<AdminRecord?> DeviceAsync(string id, CancellationToken ct)
    {
        var x = await db.DeviceRegistrations.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted).SingleOrDefaultAsync(x => x.Id == id, ct);
        return x is null ? null : new(x.Id, x.DeviceModel ?? x.DeviceType, x.DeviceType, x.IsActive ? "Còn hiệu lực" : "Đã thu hồi", DeviceVersion(x),
            [new("ID hồ sơ", x.ElderProfileId), new("Heartbeat", Time(x.LastHeartbeat)), new("Pin", x.WatchBatteryLevel is int b ? $"{b}%" : "Chưa có dữ liệu")]);
    }

    public async Task<AdminRecord?> RecordAsync(string kind, string id, CancellationToken ct)
    {
        if (kind == "accounts") return await AccountAsync(id, ct);
        if (kind == "devices") return await DeviceAsync(id, ct);
        if (kind == "staff")
        {
            if (id == "new") return new("new", "Thêm nhân sự", "Tài khoản nội bộ, không gửi email tự động", "Mới", "new", []);
            var s = await db.Set<AdminUser>().AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
            return s is null ? null : new(s.Id, s.FullName, s.NormalizedEmail, s.IsActive ? "Hoạt động" : "Tạm ngưng", Convert.ToBase64String(s.RowVersion),
                [new("Vai trò", s.Role), new("Hoạt động", s.IsActive ? "true" : "false"), new("Đăng nhập gần nhất", Time(s.LastLoginAtUtc))]);
        }
        if (kind == "care-links")
        {
            var l = await db.ElderCaregivers.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted)
                .Select(x => new { Link = x, Name = x.Caregiver.FullName, Elder = x.ElderProfile.FullName }).SingleOrDefaultAsync(x => x.Link.Id == id, ct);
            if (l is null) return null;
            var group = await db.ElderCaregivers.AsNoTracking().Where(x => x.ElderProfileId == l.Link.ElderProfileId).ToArrayAsync(ct);
            return new(l.Link.Id, l.Elder, l.Name, l.Link.IsActive ? "Đang liên kết" : "Đã ngừng", LinkGroupVersion(group),
                [new("Vai trò", l.Link.Role.ToString()), new("ID người thân", l.Link.CaregiverId)]);
        }
        if (kind == "feedback")
        {
            var f = await db.Set<CustomerFeedback>().Include(x => x.Caregiver).AsNoTracking().SingleOrDefaultAsync(x => x.Id == id, ct);
            return f is null ? null : new(f.Id, f.Subject, f.Category, f.Status, Version(new { f.Status, f.AdminReply, f.RepliedAtUtc }),
                [new("Người gửi", $"{f.Caregiver?.FullName ?? "N/A"} ({f.CaregiverId})"), new("Nội dung khách hàng", f.Message), new("Trả lời hiện tại", f.AdminReply ?? ""), new("Thời điểm gửi", Time(f.CreatedAtUtc))]);
        }
        if (kind == "elders")
        {
            var e = await db.ElderProfiles.AsNoTracking().Where(x => !x.IsDeleted).Select(x => new { x.Id, x.FullName, x.DateOfBirth }).SingleOrDefaultAsync(x => x.Id == id, ct);
            if (e is null) return null;
            var links = await db.ElderCaregivers.AsNoTracking().Where(x => x.IsActive && x.ElderProfileId == id).Select(x => new { x.Caregiver.FullName, x.Role }).ToArrayAsync(ct);
            var devices = await db.DeviceRegistrations.AsNoTracking().Where(x => x.ElderProfileId == id).Select(x => new { x.DeviceModel, x.DeviceType, x.IsActive, x.LastHeartbeat }).ToArrayAsync(ct);
            var invitations = await db.FamilyInvitations.AsNoTracking().Where(x => x.ElderProfileId == id).OrderByDescending(x => x.CreatedAt).Take(10)
                .Select(x => new { x.IsUsed, x.ExpiresAt }).ToArrayAsync(ct);
            var fields = new List<AdminField> { new("Năm sinh", e.DateOfBirth.Year.ToString()) };
            fields.AddRange(links.Select(l => new AdminField("Người chăm sóc", $"{l.FullName} · {l.Role}")));
            fields.AddRange(devices.Select(d => new AdminField("Thiết bị", $"{d.DeviceModel ?? d.DeviceType} · {(d.IsActive ? "Còn hiệu lực" : "Đã thu hồi")} · heartbeat {Time(d.LastHeartbeat)}")));
            fields.AddRange(invitations.Select(i => new AdminField("Lời mời", $"{(i.IsUsed ? "Đã dùng" : "Chưa dùng")} · hạn {Time(i.ExpiresAt)}")));
            return new(e.Id, e.FullName, "Hồ sơ và liên kết", "Chỉ đọc metadata", "read-only", fields);
        }
        return null;
    }

    public async Task<AdminIncidentDetail?> IncidentAsync(string id, CancellationToken ct)
    {
        var x = await db.Incidents.AsNoTracking().Where(x => !x.ElderProfile.IsDeleted).Select(x => new { x.Id, Name = x.ElderProfile.FullName, x.EmergencyType, x.Severity, x.Status, x.TriggeredAt, x.AcknowledgedAt, x.ResolvedAt }).SingleOrDefaultAsync(x => x.Id == id, ct);
        if (x is null) return null;
        var timeline = await db.IncidentTimelineEvents.AsNoTracking().Where(e => e.IncidentId == id).OrderBy(e => e.RecordedAt).ThenBy(e => e.Id)
            .Select(e => new { e.EventType, e.RecordedAt, e.ActorCaregiverId, e.AlertCycleNumber }).ToArrayAsync(ct);
        return new(new(x.Id, x.Name, x.EmergencyType, x.Severity.ToString(), x.Status.ToString(), Utc(x.TriggeredAt)),
            x.AcknowledgedAt is DateTime a ? Utc(a) : null, x.ResolvedAt is DateTime r ? Utc(r) : null,
            timeline.Select(e => new AdminTimelineItem(e.EventType, Utc(e.RecordedAt), e.ActorCaregiverId, e.AlertCycleNumber)).ToArray());
    }
    private static int Clamp(int page, int count) => Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(count / 25d)));
}
