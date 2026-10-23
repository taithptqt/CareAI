using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class IncidentModel(AdminApiClient api) : PageModel
{
    public AdminIncidentDetail Data { get; private set; } = null!;
    public async Task OnGetAsync(string id, CancellationToken ct) => Data = await api.GetAsync<AdminIncidentDetail>($"operations/incident/{Uri.EscapeDataString(id)}/timeline", ct);
}
