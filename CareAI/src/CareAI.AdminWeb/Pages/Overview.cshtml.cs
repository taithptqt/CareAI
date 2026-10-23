using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class OverviewModel(AdminDataSource data) : PageModel
{
    public AdminOverviewResponse Data { get; private set; } = null!;
    public async Task OnGetAsync(CancellationToken ct) => Data = await data.OverviewAsync(ct);
}
