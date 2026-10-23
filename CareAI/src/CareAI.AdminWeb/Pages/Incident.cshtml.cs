using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class IncidentModel(AdminDataSource data) : PageModel
{
    public AdminIncidentDetail Data { get; private set; } = null!;
    public async Task<IActionResult> OnGetAsync(string id, CancellationToken ct)
    {
        var detail = await data.IncidentDetailAsync(id, ct);
        if (detail is null) return NotFound();
        Data = detail;
        return Page();
    }
}
