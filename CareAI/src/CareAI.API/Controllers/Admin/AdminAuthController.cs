using CareAI.API.Admin;
using CareAI.Core.DTOs.Admin;
using CareAI.Infrastructure.Admin;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace CareAI.API.Controllers.Admin;

[ApiController]
[Route("api/v1/admin/auth")]
public sealed class AdminAuthController(AdminAuthService auth, AdminSecurityOptions settings) : ControllerBase
{
    [HttpPost("mfa/enroll"), Authorize(AuthenticationSchemes = AdminSecurity.Scheme), EnableRateLimiting("admin-mfa")]
    public async Task<IActionResult> EnrollMfa(AdminMfaRequest request, [FromServices] AdminMfaService mfa, CancellationToken ct)
    {
        var secret = await mfa.EnrollAsync(User.FindFirst("sub")!.Value, request.Password, request.Code, HttpContext.TraceIdentifier, ct);
        return Ok(new AdminMfaEnrollment(secret, secret is null));
    }
    [HttpPost("login"), AllowAnonymous, EnableRateLimiting("admin-login")]
    public async Task<IActionResult> Login(AdminLoginRequest request, CancellationToken ct)
    {
        Response.Headers.CacheControl = "no-store";
        if (!settings.Enabled) return NotFound();
        if (!Request.IsHttps) return Problem(statusCode: 400, title: "HTTPS required.");
        var result = await auth.LoginAsync(request, HttpContext.TraceIdentifier, ct);
        if (result is null) return Problem(statusCode: 401, title: "Không thể đăng nhập bằng thông tin đã cung cấp.");
        var (user, session) = result.Value;
        return Ok(new AdminLoginResponse(AdminSecurity.IssueToken(user, session, settings),
            new DateTimeOffset(DateTime.SpecifyKind(session.ExpiresAtUtc, DateTimeKind.Utc)),
            new(user.Id, user.FullName, user.Role, session.IsEnrollmentOnly ? [] : AdminPermissions.ForRole(user.Role))));
    }

    [HttpGet("me"), Authorize(AuthenticationSchemes = AdminSecurity.Scheme)]
    public IActionResult Me() => Ok(new AdminIdentity(User.FindFirst("sub")!.Value,
        User.Identity!.Name ?? "", User.FindFirst("admin_role")!.Value,
        User.FindAll("admin_permission").Select(x => x.Value).ToArray()));

    [HttpPost("logout"), Authorize(AuthenticationSchemes = AdminSecurity.Scheme)]
    public async Task<IActionResult> Logout(CancellationToken ct)
    {
        await auth.LogoutAsync(User.FindFirst("sub")!.Value, User.FindFirst("sid")!.Value, HttpContext.TraceIdentifier, ct);
        return NoContent();
    }
}
