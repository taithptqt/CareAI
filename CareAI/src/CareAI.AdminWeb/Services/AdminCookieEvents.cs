using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace CareAI.AdminWeb.Services;

public sealed class AdminCookieEvents(AdminApiClient api) : CookieAuthenticationEvents
{
    public override async Task ValidatePrincipal(CookieValidatePrincipalContext context)
    {
        if (context.Request.Path == "/Error") return; // Error rendering must survive API downtime.
        var token = context.Properties.GetTokenValue("access_token");
        if (token is null) { context.RejectPrincipal(); return; }
        try
        {
            var user = await api.MeAsync(token, context.HttpContext.RequestAborted);
            var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, user.Id), new(ClaimTypes.Name, user.FullName), new(ClaimTypes.Role, user.Role) };
            claims.AddRange(user.Permissions.Select(p => new Claim("admin_permission", p)));
            context.ReplacePrincipal(new ClaimsPrincipal(new ClaimsIdentity(claims, "AdminCookie")));
        }
        catch (AdminApiException error) when (error.StatusCode is 401 or 403)
        {
            context.RejectPrincipal();
            await context.HttpContext.SignOutAsync();
        }
        // Dependency failures propagate to the safe error page; never treat API failure as valid auth.
    }
}
