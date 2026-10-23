using System.ComponentModel.DataAnnotations;

namespace CareAI.Core.DTOs.Admin;

public sealed class AdminLoginRequest(string email, string password)
{
    [Required, MaxLength(254)] public string Email { get; init; } = email;
    [Required, StringLength(256, MinimumLength = 1)] public string Password { get; init; } = password;
    [RegularExpression("^[0-9]{6}$")] public string? OtpCode { get; init; }
}
public sealed record AdminIdentity(string Id, string FullName, string Role, IReadOnlyList<string> Permissions);
public sealed record AdminLoginResponse(string AccessToken, DateTimeOffset ExpiresAtUtc, AdminIdentity User);
public sealed class AdminMfaRequest
{
    [Required, StringLength(256)] public string Password { get; set; } = "";
    [RegularExpression("^[0-9]{6}$")] public string? Code { get; set; }
}
public sealed record AdminMfaEnrollment(string? Secret, bool Enabled);
public sealed record AdminAuditSummary(string Id, string ActorId, string Action, string TargetId,
    string Result, string TraceId, DateTimeOffset OccurredAtUtc);

public static class AdminPermissions
{
    public const string Overview = "admin.overview.read";
    public const string Accounts = "admin.accounts.read";
    public const string Incidents = "admin.incidents.read";
    public const string Devices = "admin.devices.read";
    public const string Audit = "admin.audit.read";
    public const string Feedback = "admin.feedback.read";
    public const string Elders = "admin.elders.read";
    public const string CareLinks = "admin.carelinks.read";
    public const string Staff = "admin.staff.manage";
    public const string Manage = "admin.operations.write";
    public static readonly string[] All = [Overview, Accounts, Incidents, Devices, Audit, Feedback, Elders, CareLinks, Staff, Manage];
    public static IReadOnlyList<string> ForRole(string role) => role switch
    {
        "Owner" => All,
        "Operations" => [Overview, Accounts, Incidents, Devices, Feedback, Elders, CareLinks, Manage],
        "Support" => [Accounts, Devices, Feedback, Elders, CareLinks],
        "Auditor" => [Audit],
        _ => []
    };
}
