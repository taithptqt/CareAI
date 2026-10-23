using System.Data;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public sealed class AdminAuthService(CareAiDbContext db, AdminMfaService mfa, AdminMfaOptions mfaOptions)
{
    public async Task<(AdminUser User, AdminSession Session)?> LoginAsync(AdminLoginRequest request, string traceId, CancellationToken ct)
    {
        return await db.Database.CreateExecutionStrategy().ExecuteAsync<(AdminUser User, AdminSession Session)?>(async () =>
        {
            db.ChangeTracker.Clear();
            await using var transaction = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            var now = DateTime.UtcNow;
            var email = request.Email.Trim().ToUpperInvariant();
            var user = await db.Set<AdminUser>().SingleOrDefaultAsync(x => x.NormalizedEmail == email, ct);
            var validPassword = AdminPasswords.Verify(request.Password, user?.PasswordHash ?? AdminPasswords.DummyHash);
            if (user is null) return null;
            var totpCounter = validPassword && user.MfaEnabled ? mfa.Verify(user, request.OtpCode) : null;
            var validMfa = !user.MfaEnabled || totpCounter is not null;
            if (!validPassword || !validMfa || !user.IsActive || user.LockoutEndUtc > now)
            {
                if (user.IsActive && user.LockoutEndUtc <= now)
                { user.FailedLoginAttempts = 0; user.LockoutEndUtc = null; }
                if (user.IsActive && !(user.LockoutEndUtc > now) && (!validPassword || !validMfa))
                {
                    user.FailedLoginAttempts++;
                    if (user.FailedLoginAttempts >= 5) user.LockoutEndUtc = now.AddMinutes(15);
                }
                db.Set<AdminAuditEvent>().Add(Audit(user.Id, "auth.login", user.Id, "Denied", traceId));
                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);
                return null;
            }
            user.FailedLoginAttempts = 0;
            user.LockoutEndUtc = null;
            user.LastLoginAtUtc = now;
            if (totpCounter is not null) user.LastTotpCounter = totpCounter.Value;
            var session = new AdminSession
            {
                IsEnrollmentOnly = mfaOptions.Required && !user.MfaEnabled,
                AdminUserId = user.Id, SecurityVersion = user.SecurityVersion,
                CreatedAtUtc = now, LastSeenAtUtc = now, ExpiresAtUtc = now.AddHours(8)
            };
            if (session.IsEnrollmentOnly) session.ExpiresAtUtc = now.AddMinutes(15);
            db.Set<AdminSession>().Add(session);
            db.Set<AdminAuditEvent>().Add(Audit(user.Id, "auth.login", session.Id, "Success", traceId));
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return ((AdminUser User, AdminSession Session)?)(user, session);
        });
    }

    public async Task<(AdminUser User, bool IsEnrollmentOnly)?> ValidateSessionAsync(string userId, string sessionId, int version, CancellationToken ct)
    {
        var now = DateTime.UtcNow;
        var cutoff = now.AddMinutes(-30);
        // Atomic predicate prevents a simultaneous logout from being overwritten by a heartbeat.
        var updated = await db.Set<AdminSession>().Where(s => s.Id == sessionId && s.AdminUserId == userId
            && s.SecurityVersion == version && s.RevokedAtUtc == null && s.ExpiresAtUtc > now
            && s.LastSeenAtUtc > cutoff && s.AdminUser.IsActive && s.AdminUser.SecurityVersion == version)
            .ExecuteUpdateAsync(set => set.SetProperty(s => s.LastSeenAtUtc, now), ct);
        if (updated != 1) return null;
        var user = await db.Set<AdminUser>().AsNoTracking().SingleAsync(x => x.Id == userId, ct);
        var enrollment = await db.Set<AdminSession>().Where(x => x.Id == sessionId).Select(x => x.IsEnrollmentOnly).SingleAsync(ct);
        return (user, enrollment);
    }

    public async Task LogoutAsync(string userId, string sessionId, string traceId, CancellationToken ct)
    {
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(ct);
            var now = DateTime.UtcNow;
            var count = await db.Set<AdminSession>().Where(x => x.Id == sessionId && x.AdminUserId == userId && x.RevokedAtUtc == null)
                .ExecuteUpdateAsync(s => s.SetProperty(x => x.RevokedAtUtc, now), ct);
            if (count > 0) db.Set<AdminAuditEvent>().Add(Audit(userId, "auth.logout", sessionId, "Success", traceId));
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
    }

    public async Task BootstrapAsync(string email, string name, string password, CancellationToken ct)
    {
        if (password.Length is < 16 or > 256 || name.Length is < 1 or > 100
            || email.Length > 254 || !new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(email))
            throw new InvalidOperationException("Bootstrap requires valid email, name and password of 16–256 characters.");
        var hash = AdminPasswords.Hash(password);
        await db.Database.CreateExecutionStrategy().ExecuteAsync(async () =>
        {
            db.ChangeTracker.Clear();
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable, ct);
            await db.Database.ExecuteSqlRawAsync("DECLARE @r int; EXEC @r = sp_getapplock @Resource = 'CareAI.AdminBootstrap', @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 10000; IF @r < 0 THROW 51000, 'Bootstrap lock unavailable', 1;", ct);
            if (await db.Set<AdminUser>().AnyAsync(ct)) throw new InvalidOperationException("Bootstrap is allowed only before the first admin exists.");
            var user = new AdminUser { NormalizedEmail = email.Trim().ToUpperInvariant(), FullName = name.Trim(), PasswordHash = hash, Role = "Owner" };
            db.Set<AdminUser>().Add(user);
            db.Set<AdminAuditEvent>().Add(Audit(user.Id, "staff.bootstrap", user.Id, "Success", "offline-bootstrap"));
            await db.SaveChangesAsync(ct);
            await tx.CommitAsync(ct);
        });
    }

    private static AdminAuditEvent Audit(string actor, string action, string target, string result, string trace) =>
        new() { ActorId = actor, Action = action, TargetId = target, Result = result, TraceId = trace };
}
