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
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
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
}
