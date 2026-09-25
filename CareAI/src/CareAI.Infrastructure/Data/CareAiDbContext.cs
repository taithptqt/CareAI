using Microsoft.EntityFrameworkCore;
using CareAI.Core.Entities;
using CareAI.Core.Enums;

namespace CareAI.Infrastructure.Data;

public class CareAiDbContext : DbContext
{
    public CareAiDbContext(DbContextOptions<CareAiDbContext> options) : base(options)
    {
    }

    public DbSet<ElderProfile> ElderProfiles => Set<ElderProfile>();
    public DbSet<DeviceRegistration> DeviceRegistrations => Set<DeviceRegistration>();
    public DbSet<Caregiver> Caregivers => Set<Caregiver>();
    public DbSet<ElderCaregiver> ElderCaregivers => Set<ElderCaregiver>();
    public DbSet<CaregiverPushToken> CaregiverPushTokens => Set<CaregiverPushToken>();
    public DbSet<Incident> Incidents => Set<Incident>();
    public DbSet<IncidentTimelineEvent> IncidentTimelineEvents => Set<IncidentTimelineEvent>();
    public DbSet<HealthMeasurement> HealthMeasurements => Set<HealthMeasurement>();
    public DbSet<NotificationOutbox> NotificationOutboxes => Set<NotificationOutbox>();
    public DbSet<ProcessedTelemetryLedger> ProcessedTelemetryLedgers => Set<ProcessedTelemetryLedger>();
    public DbSet<FamilyInvitation> FamilyInvitations => Set<FamilyInvitation>();
    public DbSet<PasswordResetToken> PasswordResetTokens => Set<PasswordResetToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // 1. ElderProfile
        modelBuilder.Entity<ElderProfile>(b =>
        {
            b.HasKey(e => e.Id);
            b.Property(e => e.FullName).HasMaxLength(100).IsRequired();
            b.Property(e => e.EmergencyContact).HasMaxLength(50);
            b.Property(e => e.PairingPin).HasMaxLength(10);
            b.Property(e => e.PairingPinHash).HasMaxLength(128);
            b.Property(e => e.IsDeleted).HasDefaultValue(false);
            b.HasQueryFilter(e => !e.IsDeleted);
        });

        // 2. DeviceRegistration
        modelBuilder.Entity<DeviceRegistration>(b =>
        {
            b.HasKey(d => d.Id);
            b.Property(d => d.DeviceTokenHash).HasMaxLength(128).IsRequired();
            b.Property(d => d.DeviceType).HasMaxLength(50).IsRequired();
            b.Property(d => d.FirmwareVersion).HasMaxLength(50).HasDefaultValue("1.0.0");
            b.HasOne(d => d.ElderProfile)
                .WithMany(e => e.Devices)
                .HasForeignKey(d => d.ElderProfileId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(d => d.ElderProfileId);
            b.HasIndex(d => d.LastHeartbeat);
        });

        // 3. Caregiver
        modelBuilder.Entity<Caregiver>(b =>
        {
            b.HasKey(c => c.Id);
            b.Property(c => c.FullName).HasMaxLength(100).IsRequired();
            b.Property(c => c.PhoneNumber).HasMaxLength(20).IsRequired();
            b.Property(c => c.Email).HasMaxLength(100).IsRequired();
            b.Property(c => c.PasswordHash).HasMaxLength(256).IsRequired();
            b.Property(c => c.FailedLoginAttempts).HasDefaultValue(0);
            b.HasIndex(c => c.Email).IsUnique();
        });

        // 4. ElderCaregiver
        modelBuilder.Entity<ElderCaregiver>(b =>
        {
            b.HasKey(ec => ec.Id);
            b.HasOne(ec => ec.ElderProfile)
                .WithMany(e => e.ElderCaregivers)
                .HasForeignKey(ec => ec.ElderProfileId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasOne(ec => ec.Caregiver)
                .WithMany(c => c.ElderCaregivers)
                .HasForeignKey(ec => ec.CaregiverId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(ec => new { ec.ElderProfileId, ec.CaregiverId }).IsUnique();
        });

        // 5. CaregiverPushToken
        modelBuilder.Entity<CaregiverPushToken>(b =>
        {
            b.HasKey(t => t.Id);
            b.Property(t => t.PushToken).HasMaxLength(500).IsRequired();
            b.HasOne(t => t.Caregiver)
                .WithMany(c => c.PushTokens)
                .HasForeignKey(t => t.CaregiverId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(t => new { t.CaregiverId, t.IsActive });
        });

        // 6. Incident & Filtered Unique Index UIX_Incidents_SingleActiveElder
        modelBuilder.Entity<Incident>(b =>
        {
            b.HasKey(i => i.Id);
            b.Property(i => i.EmergencyType).HasMaxLength(50).IsRequired();
            b.Property(i => i.Severity).HasConversion<int>().IsRequired();
            b.Property(i => i.Status).HasConversion<int>().IsRequired();
            b.Property(i => i.RowVersion).IsRowVersion();

            b.HasOne(i => i.ElderProfile)
                .WithMany(e => e.Incidents)
                .HasForeignKey(i => i.ElderProfileId)
                .OnDelete(DeleteBehavior.Cascade);

            // BẤT BIẾN KỸ THUẬT: Filtered Unique Index chỉ cho phép duy nhất 1 sự cố Active (Open hoặc Acknowledged)
            b.HasIndex(i => i.ElderProfileId)
                .HasDatabaseName("UIX_Incidents_SingleActiveElder")
                .IsUnique()
                .HasFilter("[Status] IN (1, 2)"); // Open = 1, Acknowledged = 2
        });

        // 7. IncidentTimelineEvent
        modelBuilder.Entity<IncidentTimelineEvent>(b =>
        {
            b.HasKey(t => t.Id);
            b.Property(t => t.EventType).HasMaxLength(50).IsRequired();
            b.HasOne(t => t.Incident)
                .WithMany(i => i.TimelineEvents)
                .HasForeignKey(t => t.IncidentId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(t => t.IncidentId);
        });

        // 8. HealthMeasurement & Deduplication Index
        modelBuilder.Entity<HealthMeasurement>(b =>
        {
            b.HasKey(m => m.Id);
            b.Property(m => m.Id).ValueGeneratedOnAdd();
            b.Property(m => m.MetricType).HasMaxLength(50).IsRequired();
            b.Property(m => m.Unit).HasMaxLength(20).IsRequired();

            b.HasOne(m => m.ElderProfile)
                .WithMany(e => e.Measurements)
                .HasForeignKey(m => m.ElderProfileId)
                .OnDelete(DeleteBehavior.Cascade);

            // BẤT BIẾN ĐA THIẾT BỊ: Khử trùng lặp trên cùng 1 thiết bị đo cùng 1 thời điểm
            b.HasIndex(m => new { m.ElderProfileId, m.DeviceId, m.Timestamp, m.MetricType })
                .HasDatabaseName("UIX_HealthMeasurements_Deduplication")
                .IsUnique();

            b.HasIndex(m => new { m.ElderProfileId, m.MetricType, m.Timestamp });
        });

        // 9. NotificationOutbox
        modelBuilder.Entity<NotificationOutbox>(b =>
        {
            b.HasKey(n => n.Id);
            b.Property(n => n.Status).HasMaxLength(20).HasDefaultValue("PENDING");
            b.HasOne(n => n.Incident)
                .WithMany()
                .HasForeignKey(n => n.IncidentId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(n => new { n.Status, n.NextRetryAt });
        });

        // 10. ProcessedTelemetryLedger (Khóa chính kép)
        modelBuilder.Entity<ProcessedTelemetryLedger>(b =>
        {
            b.HasKey(p => new { p.DeviceId, p.PacketId })
                .HasName("PK_ProcessedTelemetryLedgers");
            b.HasIndex(p => p.ReceivedAt);
        });

        // 11. FamilyInvitation (Mã mời gia đình 6 ký tự, TTL 24h)
        modelBuilder.Entity<FamilyInvitation>(b =>
        {
            b.HasKey(f => f.Id);
            b.Property(f => f.InvitationCode).HasMaxLength(10).IsRequired();
            b.Property(f => f.InvitationCodeHash).HasMaxLength(128).IsRequired();
            b.HasOne(f => f.ElderProfile)
                .WithMany()
                .HasForeignKey(f => f.ElderProfileId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasOne(f => f.InvitedByCaregiver)
                .WithMany()
                .HasForeignKey(f => f.InvitedByCaregiverId)
                .OnDelete(DeleteBehavior.NoAction);
            b.HasIndex(f => f.InvitationCodeHash);
            b.HasIndex(f => f.ExpiresAt);
        });

        // 12. PasswordResetToken (OTP 6 số qua Email, TTL 10 phút)
        modelBuilder.Entity<PasswordResetToken>(b =>
        {
            b.HasKey(p => p.Id);
            b.Property(p => p.OtpCode).HasMaxLength(10).IsRequired();
            b.Property(p => p.OtpHash).HasMaxLength(128).IsRequired();
            b.HasOne(p => p.Caregiver)
                .WithMany()
                .HasForeignKey(p => p.CaregiverId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(p => p.OtpHash);
            b.HasIndex(p => p.ExpiresAt);
        });
    }
}
