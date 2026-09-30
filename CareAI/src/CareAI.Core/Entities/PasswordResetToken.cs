namespace CareAI.Core.Entities;

/// <summary>
/// Token đặt lại mật khẩu qua OTP 6 số gửi Email (TTL 10 phút)
/// </summary>
public class PasswordResetToken
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string CaregiverId { get; set; } = string.Empty;
    public Caregiver Caregiver { get; set; } = null!;

    /// <summary>
    /// Mã OTP 6 số (VD: "482917")
    /// </summary>
    public string OtpCode { get; set; } = string.Empty;

    /// <summary>
    /// Băm SHA-256 lowercase của OTP
    /// </summary>
    public string OtpHash { get; set; } = string.Empty;

    public bool IsUsed { get; set; } = false;
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
