namespace CareAI.Core.Entities.Admin;

public sealed class AdminUser
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string FullName { get; set; } = "";
    public string NormalizedEmail { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public string Role { get; set; } = "Support";
    public bool IsActive { get; set; } = true;
    public int SecurityVersion { get; set; } = 1;
    public int FailedLoginAttempts { get; set; }
    public DateTime? LockoutEndUtc { get; set; }
    public DateTime? LastLoginAtUtc { get; set; }
    public bool MfaEnabled { get; set; }
    public string? MfaSecretProtected { get; set; }
    public string? PendingMfaSecretProtected { get; set; }
    public long LastTotpCounter { get; set; } = -1;
    public byte[] RowVersion { get; set; } = [];
}

public sealed class AdminSession
{
    public bool IsEnrollmentOnly { get; set; }
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string AdminUserId { get; set; } = "";
    public AdminUser AdminUser { get; set; } = null!;
    public int SecurityVersion { get; set; }
    public DateTime CreatedAtUtc { get; set; }
    public DateTime LastSeenAtUtc { get; set; }
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime? RevokedAtUtc { get; set; }
}

public sealed class AdminAuditEvent
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ActorId { get; set; } = "";
    public string Action { get; set; } = "";
    public string TargetId { get; set; } = "";
    public string Result { get; set; } = "";
    public string Reason { get; set; } = "";
    public string TraceId { get; set; } = "";
    public DateTime OccurredAtUtc { get; set; } = DateTime.UtcNow;
    public string? ChangesJson { get; set; }
}
