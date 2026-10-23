using System.Data;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities;
using CareAI.Core.Entities.Admin;
using CareAI.Core.Enums;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public sealed record AdminCommandOptions(string FingerprintKey, bool CaregiverApiEnforcementReady = false);
public sealed class AdminBusinessException(string message, int status = 409) : Exception(message)
{ public int Status { get; } = status; }

public sealed class AdminCommandService(CareAiDbContext db, AdminCommandOptions options, Microsoft.Extensions.Caching.Memory.IMemoryCache? cache = null)
{
    public async Task<AdminCommandResult> ExecuteAsync(string actorId, string sessionId, AdminCommandRequest request, string traceId, CancellationToken ct)
    {
        if (!Guid.TryParse(request.RequestId, out _) || request.Reason.Trim().Length < 5
            || request.Values.Count > 8 || request.Values.Any(v => v.Key.Length > 40 || v.Value is null || v.Value.Length > 3000))
            throw new AdminBusinessException("Dữ liệu biểu mẫu không hợp lệ.", 400);
        var fingerprint = Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(options.FingerprintKey),
            Encoding.UTF8.GetBytes(JsonSerializer.Serialize(new { request.Action, request.TargetId, request.ExpectedVersion, Reason = request.Reason.Trim(), Values = request.Values.OrderBy(x => x.Key).ToArray() }))));
        return await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            if (db.Database.IsSqlServer())
            {
                await db.Database.ExecuteSqlRawAsync("DECLARE @r int; EXEC @r=sp_getapplock @Resource=N'CareAI.AdminCommands', @LockMode=N'Exclusive', @LockOwner=N'Transaction', @LockTimeout=10000; IF @r<0 THROW 51000,'Admin command lock unavailable',1;", ct);
            }
            var now = DateTime.UtcNow;
            var session = await db.Set<AdminSession>().Include(x => x.AdminUser).SingleOrDefaultAsync(x => x.Id == sessionId && x.AdminUserId == actorId, ct);
            if (session is null || session.RevokedAtUtc != null || session.ExpiresAtUtc <= now || session.LastSeenAtUtc <= now.AddMinutes(-30)
                || !session.AdminUser.IsActive || session.SecurityVersion != session.AdminUser.SecurityVersion)
                throw new AdminBusinessException("Phiên không còn hợp lệ.", 401);
            if (session.IsEnrollmentOnly) throw new AdminBusinessException("Hoàn tất thiết lập MFA trước khi thao tác quản trị.", 403);
            var actor = session.AdminUser;
            var permission = request.Action.StartsWith("staff.", StringComparison.Ordinal) ? AdminPermissions.Staff : AdminPermissions.Manage;
            if (!AdminPermissions.ForRole(actor.Role).Contains(permission)) throw new AdminBusinessException("Không có quyền thực hiện.", 403);
            if (!AdminPasswords.Verify(request.ReauthPassword, actor.PasswordHash)) throw new AdminBusinessException("Mật khẩu xác thực lại không đúng.", 403);
            var previous = await db.Set<AdminCommandRecord>().SingleOrDefaultAsync(x => x.ActorId == actorId && x.RequestId == request.RequestId, ct);
            if (previous is not null)
            {
                if (previous.PayloadFingerprint != fingerprint) throw new AdminBusinessException("Mã yêu cầu đã được dùng với nội dung khác. Tải lại trước khi gửi.");
                return new AdminCommandResult(previous.TargetId, "Yêu cầu này đã được thực hiện thành công trước đó.");
            }
            var target = request.TargetId;
            switch (request.Action)
            {
                case "account.update":
                case "account.unlock":
                case "account.suspend":
                case "account.restore":
                case "account.revoke":
                    var account = await db.Caregivers.SingleOrDefaultAsync(x => x.Id == target, ct) ?? throw Missing();
                    var state = await db.Set<CaregiverAdminState>().SingleOrDefaultAsync(x => x.CaregiverId == target, ct);
                    Check(request.ExpectedVersion, AdminOperationsReadService.AccountVersion(account, state));
                    if (request.Action == "account.unlock") { account.LockoutEnd = null; account.FailedLoginAttempts = 0; }
                    else if (request.Action == "account.update")
                    {
                        account.FullName = Value(request, "FullName", 3, 100);
                        var phone = Value(request, "PhoneNumber", 0, 20);
                        if (phone.Length > 0 && !System.Text.RegularExpressions.Regex.IsMatch(phone, @"^\+?[0-9 ()-]{8,20}$")) throw new AdminBusinessException("Số điện thoại không hợp lệ.", 400);
                        account.PhoneNumber = phone;
                    }
                    else
                    {
                        if (!options.CaregiverApiEnforcementReady) throw new AdminBusinessException("API ứng dụng trên Azure chưa xác nhận hỗ trợ đình chỉ/thu hồi JWT. Cần deploy cơ chế kiểm tra phiên trước khi bật thao tác này.");
                        if (request.Action == "account.suspend")
                        {
                            if (await db.Incidents.AnyAsync(x => x.AcknowledgedByCaregiverId == target && (x.Status == IncidentStatus.Open || x.Status == IncidentStatus.Acknowledged), ct))
                                throw new AdminBusinessException("Người thân đang tiếp nhận một sự cố chưa giải quyết.");
                            var affected = await db.ElderCaregivers.Where(x => x.CaregiverId == target && x.IsActive).ToArrayAsync(ct);
                            foreach (var relation in affected)
                            {
                                if (!await db.ElderCaregivers.AnyAsync(x => x.ElderProfileId == relation.ElderProfileId && x.CaregiverId != target && x.IsActive
                                    && (relation.Role != CaregiverRole.Primary || x.Role == CaregiverRole.Primary)
                                    && !db.Set<CaregiverAdminState>().Any(s => s.CaregiverId == x.CaregiverId && s.IsSuspended)
                                    && db.CaregiverPushTokens.Any(t => t.CaregiverId == x.CaregiverId && t.IsActive), ct))
                                    throw new AdminBusinessException("Chưa có người chăm sóc thay thế hoạt động với kênh nhận cảnh báo. Xử lý liên kết và kiểm tra cảnh báo trước.");
                            }
                        }
                        if (state is null) { state = new() { CaregiverId = target }; db.Set<CaregiverAdminState>().Add(state); }
                        if (request.Action != "account.revoke") state.IsSuspended = request.Action == "account.suspend";
                        state.SecurityVersion++; state.Reason = request.Reason.Trim(); state.UpdatedAtUtc = now;
                    }
                    cache?.Remove($"auth:caregiver:{target}");
                    break;
                case "device.revoke":
                    var device = await db.DeviceRegistrations.SingleOrDefaultAsync(x => x.Id == target && !x.ElderProfile.IsDeleted, ct) ?? throw Missing();
                    Check(request.ExpectedVersion, AdminOperationsReadService.DeviceVersion(device));
                    if (await ActiveIncident(device.ElderProfileId, ct)) throw new AdminBusinessException("Không thu hồi thiết bị khi hồ sơ đang có sự cố chưa giải quyết.");
                    if (await db.DeviceRegistrations.CountAsync(x => x.ElderProfileId == device.ElderProfileId && x.IsActive, ct) <= 1 && device.IsActive)
                        throw new AdminBusinessException("Đây là thiết bị còn hiệu lực cuối cùng. Ghép thiết bị thay thế trước khi thu hồi.");
                    device.IsActive = false; device.UpdatedAt = now;
                    cache?.Remove($"auth:dev:{target}");
                    break;
                case "link.primary":
                case "link.deactivate":
                    var link = await db.ElderCaregivers.Include(x => x.ElderProfile).SingleOrDefaultAsync(x => x.Id == target && !x.ElderProfile.IsDeleted, ct) ?? throw Missing();
                    var linkGroup = await db.ElderCaregivers.Where(x => x.ElderProfileId == link.ElderProfileId).ToArrayAsync(ct);
                    Check(request.ExpectedVersion, AdminOperationsReadService.LinkGroupVersion(linkGroup));
                    if (!link.IsActive) throw new AdminBusinessException("Liên kết không còn hiệu lực.");
                    if (await db.Set<CaregiverAdminState>().AnyAsync(x => x.CaregiverId == link.CaregiverId && x.IsSuspended, ct)) throw new AdminBusinessException("Không chuyển quyền cho tài khoản đang đình chỉ.");
                    // Any active incident blocks reassignment in this MVP, preserving the responder/alert path.
                    if (await ActiveIncident(link.ElderProfileId, ct)) throw new AdminBusinessException("Chỉ thay đổi liên kết sau khi gia đình giải quyết sự cố đang mở.");
                    if (request.Action == "link.deactivate")
                    {
                        if (link.Role == CaregiverRole.Primary) throw new AdminBusinessException("Chuyển vai trò chính sang người thay thế trước khi ngừng liên kết này.");
                        if (!await db.ElderCaregivers.AnyAsync(x => x.ElderProfileId == link.ElderProfileId && x.Id != target && x.IsActive && x.Role == CaregiverRole.Primary, ct))
                            throw new AdminBusinessException("Hồ sơ chưa có người chăm sóc chính hoạt động.");
                        link.IsActive = false;
                    }
                    else
                    {
                        var group = linkGroup.Where(x => x.IsActive);
                        foreach (var relation in group) relation.Role = relation.Id == link.Id ? CaregiverRole.Primary : CaregiverRole.Secondary;
                    }
                    break;
                case "staff.create":
                    if (request.ExpectedVersion != "new") throw new AdminBusinessException("Biểu mẫu tạo tài khoản không hợp lệ.", 400);
                    var login = Value(request, "Login", 3, 100).ToUpperInvariant();
                    if (!System.Text.RegularExpressions.Regex.IsMatch(login, @"^[A-Z0-9@._+-]+$")) throw new AdminBusinessException("Tên đăng nhập chỉ dùng chữ, số, @ . _ + -.", 400);
                    if (await db.Set<AdminUser>().AnyAsync(x => x.NormalizedEmail == login, ct)) throw new AdminBusinessException("Tên đăng nhập đã tồn tại.");
                    var password = request.Values.GetValueOrDefault("NewPassword") ?? "";
                    if (password.Length is < 16 or > 256) throw new AdminBusinessException("Mật khẩu nhân sự cần 16–256 ký tự.", 400);
                    var newStaff = new AdminUser { FullName = Value(request, "FullName", 3, 100), NormalizedEmail = login,
                        PasswordHash = AdminPasswords.Hash(password), Role = Role(Value(request, "Role", 1, 30)) };
                    db.Set<AdminUser>().Add(newStaff); target = newStaff.Id;
                    break;
                case "staff.update":
                case "staff.revoke":
                    var staff = await db.Set<AdminUser>().SingleOrDefaultAsync(x => x.Id == target, ct) ?? throw Missing();
                    Check(request.ExpectedVersion, Convert.ToBase64String(staff.RowVersion));
                    if (actorId == target && request.Action == "staff.update") throw new AdminBusinessException("Không tự thay đổi vai trò hoặc vô hiệu hóa tài khoản hiện tại.");
                    if (request.Action == "staff.update")
                    {
                        var nextRole = Role(Value(request, "Role", 1, 30));
                        var active = Value(request, "IsActive", 4, 5) == "true";
                        if (staff.IsActive && staff.Role == "Owner" && (!active || nextRole != "Owner")
                            && await db.Set<AdminUser>().CountAsync(x => x.IsActive && x.Role == "Owner", ct) <= 1)
                            throw new AdminBusinessException("Không thể vô hiệu hóa hoặc hạ quyền chủ hệ thống cuối cùng.");
                        staff.Role = nextRole; staff.IsActive = active;
                    }
                    staff.SecurityVersion++;
                    await db.Set<AdminSession>().Where(x => x.AdminUserId == target && x.RevokedAtUtc == null)
                        .ExecuteUpdateAsync(set => set.SetProperty(x => x.RevokedAtUtc, now), ct);
                    break;
                case "feedback.reply":
                    var feedback = await db.Set<CustomerFeedback>().SingleOrDefaultAsync(x => x.Id == target, ct) ?? throw Missing();
                    Check(request.ExpectedVersion, AdminOperationsReadService.Version(new { feedback.Status, feedback.AdminReply, feedback.RepliedAtUtc }));
                    var status = Value(request, "Status", 1, 20);
                    if (status is not ("InProgress" or "Resolved")) throw new AdminBusinessException("Trạng thái phản hồi không hợp lệ.", 400);
                    feedback.AdminReply = Value(request, "Reply", 5, 3000); feedback.Status = status; feedback.RepliedAtUtc = now;
                    break;
                default: throw new AdminBusinessException("Thao tác không được hỗ trợ.", 400);
            }
            db.Set<AdminAuditEvent>().Add(new() { ActorId = actorId, Action = request.Action, TargetId = target,
                Reason = request.Reason.Trim(), Result = "Success", TraceId = traceId, OccurredAtUtc = now,
                ChangesJson = JsonSerializer.Serialize(request.Action switch
                {
                    "account.update" => (object)new { Fields = new[] { "FullName", "PhoneNumber" } },
                    "staff.create" or "staff.update" => new { Fields = new[] { "Role", "IsActive" }, Role = request.Values.GetValueOrDefault("Role"), Active = request.Values.GetValueOrDefault("IsActive") },
                    "feedback.reply" => new { Fields = new[] { "Reply", "Status" }, Status = request.Values.GetValueOrDefault("Status") },
                    _ => new { Action = request.Action }
                }) });
            db.Set<AdminCommandRecord>().Add(new() { ActorId = actorId, RequestId = request.RequestId, PayloadFingerprint = fingerprint, TargetId = target });
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return new AdminCommandResult(target, request.Action == "device.revoke" ? "Đã thu hồi quyền thiết bị thành công (Cache xác thực đã được giải phóng tức thì)." : "Đã cập nhật và ghi nhật ký thành công.");
        });
    }
    private Task<bool> ActiveIncident(string elderId, CancellationToken ct) => db.Incidents.AnyAsync(x => x.ElderProfileId == elderId && (x.Status == IncidentStatus.Open || x.Status == IncidentStatus.Acknowledged), ct);
    private static void Check(string expected, string actual) { if (expected != actual) throw new AdminBusinessException("Dữ liệu đã thay đổi. Tải lại và kiểm tra trước khi gửi."); }
    private static AdminBusinessException Missing() => new("Không tìm thấy đối tượng.", 404);
    private static string Role(string value) => value is "Owner" or "Operations" or "Support" or "Auditor" ? value : throw new AdminBusinessException("Vai trò không hợp lệ.", 400);
    private static string Value(AdminCommandRequest request, string key, int min, int max)
    {
        var value = request.Values.GetValueOrDefault(key)?.Trim() ?? "";
        if (value.Length < min || value.Length > max) throw new AdminBusinessException($"Trường {key} cần {min}–{max} ký tự.", 400);
        return value;
    }
}
