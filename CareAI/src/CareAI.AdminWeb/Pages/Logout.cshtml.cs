using CareAI.AdminWeb.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class LogoutModel(AdminApiClient api) : PageModel
{
    public IActionResult OnGet() => RedirectToPage("/Overview");
    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        // If remote revocation fails, show an error and keep the session available to retry.
        await api.LogoutAsync(ct);
        await HttpContext.SignOutAsync("AdminCookie");
        return RedirectToPage("/Login");
    }
}
