using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;

public abstract class AdminModulePageModel(AdminApiClient api, AdminWebMode mode, string kind) : PageModel
{
    public string Kind => kind;
    public bool Preview => mode.Preview;
    public string PageRoute => Kind switch { "staff" => "/Staff", "elders" => "/Elders", "care-links" => "/CareLinks", _ => "" };
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public AdminListResponse<AdminRecord> Data { get; private set; } = null!;
    public async Task<IActionResult> OnGetAsync(CancellationToken ct)
    {
        if ((Search?.Length ?? 0) > 120) return BadRequest();
        Data = mode.Preview ? new([], 0, 1, 25, DateTimeOffset.UtcNow)
            : await api.GetAsync<AdminListResponse<AdminRecord>>($"operations/{kind}?search={Uri.EscapeDataString(Search?.Trim() ?? "")}&page={Math.Max(1, PageNumber)}", ct);
        PageNumber = Data.Page;
        return Page();
    }
}
public sealed class StaffModel(AdminApiClient api, AdminWebMode mode) : AdminModulePageModel(api, mode, "staff");
public sealed class EldersModel(AdminApiClient api, AdminWebMode mode) : AdminModulePageModel(api, mode, "elders");
public sealed class CareLinksModel(AdminApiClient api, AdminWebMode mode) : AdminModulePageModel(api, mode, "care-links");
