using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages.Accounts;

public sealed class IndexModel(AdminDataSource data, AdminWebMode mode) : PageModel
{
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public string? Status { get; set; }
    [BindProperty(SupportsGet = true)] public bool Locked { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public const int PageSize = 25;
    public bool Preview => mode.Preview;
    public AdminListResponse<AdminAccountSummary> Results { get; private set; } = null!;
    public int PageCount => Math.Max(1, (int)Math.Ceiling(Results.TotalCount / (double)PageSize));

    public async Task<IActionResult> OnGetAsync(CancellationToken ct)
    {
        if ((Search?.Length ?? 0) > 120 || (Status is not null && Status is not ("Active" or "Suspended" or "")))
            return BadRequest("Bộ lọc không hợp lệ.");
        Search = Search?.Trim();
        Results = await data.AccountsAsync(Search, Status, Locked, PageNumber, ct);
        PageNumber = Results.Page;
        return Page();
    }
}
