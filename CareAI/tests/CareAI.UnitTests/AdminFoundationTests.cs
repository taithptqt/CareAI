using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;

public sealed class AdminFoundationTests
{
    [Fact]
    public void CareLinkGroupVersionChangesWhenAnotherPrimaryChanges()
    {
        var group = new[] {
            new CareAI.Core.Entities.ElderCaregiver { Id = "a", CaregiverId = "fictional-a", Role = CareAI.Core.Enums.CaregiverRole.Primary },
            new CareAI.Core.Entities.ElderCaregiver { Id = "b", CaregiverId = "fictional-b" },
            new CareAI.Core.Entities.ElderCaregiver { Id = "c", CaregiverId = "fictional-c" }
        };
        var before = AdminOperationsReadService.LinkGroupVersion(group);
        Assert.Equal(before, AdminOperationsReadService.LinkGroupVersion(group.Reverse()));
        var unchangedTarget = AdminOperationsReadService.LinkVersion(group[2]);
        group[0].Role = CareAI.Core.Enums.CaregiverRole.Secondary;
        group[1].Role = CareAI.Core.Enums.CaregiverRole.Primary;
        Assert.Equal(unchangedTarget, AdminOperationsReadService.LinkVersion(group[2]));
        Assert.NotEqual(before, AdminOperationsReadService.LinkGroupVersion(group));
    }
    [Fact]
    public void PasswordHashesUseFreshSaltAndRejectWrongPasswords()
    {
        const string password = "fictional-admin-password-for-unit-test";
        var first = AdminPasswords.Hash(password);
        var second = AdminPasswords.Hash(password);
        Assert.NotEqual(first, second);
        Assert.True(AdminPasswords.Verify(password, first));
        Assert.False(AdminPasswords.Verify("incorrect", first));
        Assert.False(AdminPasswords.Verify(password, "not:a:valid:hash"));
        Assert.False(AdminPasswords.Verify(password, "invalid:base64"));
    }

    [Fact]
    public void CaregiverRolesAndUnknownRolesNeverGrantAdminPermissions()
    {
        Assert.Empty(AdminPermissions.ForRole("Caregiver"));
        Assert.Empty(AdminPermissions.ForRole("Primary"));
        Assert.Empty(AdminPermissions.ForRole("Secondary"));
        Assert.Empty(AdminPermissions.ForRole("unknown"));
        Assert.DoesNotContain(AdminPermissions.Audit, AdminPermissions.ForRole("Support"));
        Assert.DoesNotContain(AdminPermissions.Incidents, AdminPermissions.ForRole("Support"));
        Assert.Equal(new[] { AdminPermissions.Audit }, AdminPermissions.ForRole("Auditor"));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task AuditCannotBeModifiedEvenWithHistoricalIncidentOverride(bool historicalOverride)
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning)).Options);
        var entry = new AdminAuditEvent { ActorId = "fictional-admin", Action = "auth.login", Result = "Success" };
        db.Set<AdminAuditEvent>().Add(entry);
        await db.SaveChangesAsync();
        db.AllowAdminHistoricalOverride = historicalOverride;
        entry.Result = "Denied";
        await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
        db.Entry(entry).State = EntityState.Unchanged;
        db.Set<AdminAuditEvent>().Remove(entry);
        await Assert.ThrowsAsync<InvalidOperationException>(() => db.SaveChangesAsync());
    }

        [Fact]
    public async Task DeviceRevocationEvictsAuthCacheKeyImmediately()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).ConfigureWarnings(w => w.Ignore(Microsoft.EntityFrameworkCore.Diagnostics.InMemoryEventId.TransactionIgnoredWarning)).Options);
        using var cache = new Microsoft.Extensions.Caching.Memory.MemoryCache(new Microsoft.Extensions.Caching.Memory.MemoryCacheOptions());
        const string deviceId = "DEV_TARGET_01";
        Microsoft.Extensions.Caching.Memory.CacheExtensions.Set(cache, $"auth:dev:{deviceId}", "cached_token_hash");
        Assert.True(cache.TryGetValue($"auth:dev:{deviceId}", out _));

        var elder = new CareAI.Core.Entities.ElderProfile { Id = "ELDER_01", FullName = "Cụ Test" };
        var dev1 = new CareAI.Core.Entities.DeviceRegistration { Id = deviceId, ElderProfileId = elder.Id, IsActive = true, DeviceTokenHash = "hash1" };
        var dev2 = new CareAI.Core.Entities.DeviceRegistration { Id = "DEV_BACKUP", ElderProfileId = elder.Id, IsActive = true, DeviceTokenHash = "hash2" };
        var admin = new AdminUser { Id = "ADMIN_01", NormalizedEmail = "ADMIN@TEST.COM", Role = "Owner", PasswordHash = AdminPasswords.Hash("AdminPassword123!") };
        var session = new AdminSession { Id = "SESS_01", AdminUserId = admin.Id, SecurityVersion = admin.SecurityVersion, ExpiresAtUtc = DateTime.UtcNow.AddHours(1), LastSeenAtUtc = DateTime.UtcNow };

        db.ElderProfiles.Add(elder);
        db.DeviceRegistrations.AddRange(dev1, dev2);
        db.Set<AdminUser>().Add(admin);
        db.Set<AdminSession>().Add(session);
        await db.SaveChangesAsync();

        var service = new AdminCommandService(db, new AdminCommandOptions("test-fingerprint-key-32-bytes-long!"), cache);
        var req = new AdminCommandRequest
        {
            Action = "device.revoke",
            TargetId = deviceId,
            ExpectedVersion = AdminOperationsReadService.DeviceVersion(dev1),
            Reason = "Thu hồi thiết bị cũ",
            ReauthPassword = "AdminPassword123!",
            RequestId = Guid.NewGuid().ToString()
        };

        var result = await service.ExecuteAsync(admin.Id, session.Id, req, "trace-test", default);
        Assert.Equal(deviceId, result.TargetId);
        Assert.False(cache.TryGetValue($"auth:dev:{deviceId}", out _));
    }
}