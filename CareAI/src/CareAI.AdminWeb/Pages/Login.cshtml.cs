using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;

public sealed class LoginModel(AdminApiClient api, AdminWebMode mode) : PageModel
{
    [BindProperty, Required, MaxLength(254)] public string Email { get; set; } = "";
    [BindProperty, Required, StringLength(256)] public string Password { get; set; } = "";
    [BindProperty, RegularExpression("^[0-9]{6}$")] public string? OtpCode { get; set; }
    public bool Live => mode.Live;
    public string? Error { get; private set; }
    public IActionResult OnGet(bool expired = false)
    {
        if (User.Identity?.IsAuthenticated == true)
            return RedirectToPage(User.HasClaim("admin_permission", AdminPermissions.Accounts) ? "/Accounts/Index"
                : User.HasClaim("admin_permission", AdminPermissions.Audit) ? "/Audit" : "/Security");
        if (expired) Error = "Biểu mẫu đăng nhập đã hết hiệu lực. Vui lòng nhập lại thông tin và đăng nhập.";
        return Page();
    }
    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!mode.Live) return NotFound();
        if (!ModelState.IsValid) return Page();
        try
        {
            var login = await api.LoginAsync(new AdminLoginRequest(Email, Password) { OtpCode = OtpCode }, ct);
            var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, login.User.Id), new(ClaimTypes.Name, login.User.FullName), new(ClaimTypes.Role, login.User.Role) };
            claims.AddRange(login.User.Permissions.Select(p => new Claim("admin_permission", p)));
            var properties = new AuthenticationProperties { ExpiresUtc = login.ExpiresAtUtc, IsPersistent = false, AllowRefresh = false };
            properties.StoreTokens([new AuthenticationToken { Name = "access_token", Value = login.AccessToken }]);
            await HttpContext.SignInAsync("AdminCookie", new ClaimsPrincipal(new ClaimsIdentity(claims, "AdminCookie")), properties);
            if (login.User.Permissions.Count == 0) return RedirectToPage("/Security");
            return RedirectToPage(login.User.Permissions.Contains(AdminPermissions.Accounts) ? "/Accounts/Index"
                : login.User.Permissions.Contains(AdminPermissions.Overview) ? "/Overview" : "/Audit");
        }
        catch (AdminApiException error)
        {
            Error = error.StatusCode == 401 ? "Không thể đăng nhập bằng thông tin đã cung cấp."
                : error.StatusCode == 429 ? "Đã vượt số lần thử. Vui lòng chờ rồi thử lại."
                : $"Không thể kết nối dịch vụ đăng nhập. Mã đối chiếu: {error.TraceId}";
            return Page();
        }
        finally { Password = ""; ModelState.Remove(nameof(Password)); }
    }
}
