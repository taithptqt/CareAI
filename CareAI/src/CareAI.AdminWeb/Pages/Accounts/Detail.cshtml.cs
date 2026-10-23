using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages.Accounts;
public sealed class DetailModel(AdminDataSource data, AdminWebMode mode, AdminPreviewData preview) : PageModel
{
    public AdminAccountSummary Account { get; private set; } = null!;
    public DateTimeOffset AsOfUtc { get; private set; }
    public async Task<IActionResult> OnGetAsync(string id, CancellationToken ct)
    {
        var account = await data.AccountAsync(id, ct);
        if (account is null) return NotFound();
        Account = account;
        AsOfUtc = mode.Preview ? preview.AsOfUtc : DateTimeOffset.UtcNow;
        return Page();
    }
}
