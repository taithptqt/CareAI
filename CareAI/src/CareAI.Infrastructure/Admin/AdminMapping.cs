using CareAI.Core.Entities.Admin;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public static class AdminMapping
{
    public static void Configure(ModelBuilder model)
    {
        model.Entity<CaregiverAdminState>(b =>
        {
            b.ToTable("CaregiverAdminStates"); b.HasKey(x => x.CaregiverId);
            b.Property(x => x.CaregiverId).HasMaxLength(50);
            b.Property(x => x.Reason).HasMaxLength(500);
            b.Property(x => x.RowVersion).IsRowVersion();
        });
        model.Entity<AdminCommandRecord>(b =>
        {
            b.ToTable("AdminCommandRecords"); b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasMaxLength(36);
            b.Property(x => x.ActorId).HasMaxLength(36);
            b.Property(x => x.RequestId).HasMaxLength(36);
            b.Property(x => x.PayloadFingerprint).HasMaxLength(64);
            b.Property(x => x.TargetId).HasMaxLength(100);
            b.HasIndex(x => new { x.ActorId, x.RequestId }).IsUnique();
        });
        model.Entity<AdminUser>(b =>
        {
            b.ToTable("AdminUsers"); b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasMaxLength(36);
            b.Property(x => x.FullName).HasMaxLength(100);
            b.Property(x => x.NormalizedEmail).HasMaxLength(254);
            b.HasIndex(x => x.NormalizedEmail).IsUnique();
            b.Property(x => x.PasswordHash).HasMaxLength(256);
            b.Property(x => x.Role).HasMaxLength(30);
            b.Property(x => x.MfaSecretProtected).HasMaxLength(2000);
            b.Property(x => x.PendingMfaSecretProtected).HasMaxLength(2000);
            b.Property(x => x.RowVersion).IsRowVersion();
        });
        model.Entity<AdminSession>(b =>
        {
            b.ToTable("AdminSessions"); b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasMaxLength(36);
            b.Property(x => x.AdminUserId).HasMaxLength(36);
            b.HasOne(x => x.AdminUser).WithMany().HasForeignKey(x => x.AdminUserId).OnDelete(DeleteBehavior.Restrict);
            b.HasIndex(x => x.ExpiresAtUtc);
        });
        model.Entity<AdminAuditEvent>(b =>
        {
            b.ToTable("AdminAuditEvents", table => table.UseSqlOutputClause(false)); b.HasKey(x => x.Id);
            b.Property(x => x.Id).HasMaxLength(36);
            b.Property(x => x.ActorId).HasMaxLength(36);
            b.Property(x => x.Action).HasMaxLength(80);
            b.Property(x => x.TargetId).HasMaxLength(100);
            b.Property(x => x.Result).HasMaxLength(30);
            b.Property(x => x.Reason).HasMaxLength(500);
            b.Property(x => x.TraceId).HasMaxLength(128);
            b.Property(x => x.ChangesJson).HasMaxLength(2000);
            b.HasIndex(x => x.OccurredAtUtc);
        });
    }
}
