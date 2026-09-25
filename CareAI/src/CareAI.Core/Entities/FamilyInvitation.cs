namespace CareAI.Core.Entities;

/// <summary>
/// Mã mời tham gia nhóm gia đình chăm sóc (6 ký tự viết hoa, TTL 24 giờ)
/// </summary>
public class FamilyInvitation
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string InvitedByCaregiverId { get; set; } = string.Empty;
    public Caregiver InvitedByCaregiver { get; set; } = null!;

    /// <summary>
    /// Mã mời 6 ký tự viết hoa (VD: "A3X7K2")
    /// </summary>
    public string InvitationCode { get; set; } = string.Empty;

    /// <summary>
    /// Băm SHA-256 lowercase của InvitationCode để lưu trong CSDL
    /// </summary>
    public string InvitationCodeHash { get; set; } = string.Empty;

    public bool IsUsed { get; set; } = false;
    public string? AcceptedByCaregiverId { get; set; }
    public DateTime? AcceptedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
