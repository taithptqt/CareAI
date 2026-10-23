using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class DevicesModel(AdminDataSource data) : PageModel
{
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public string? Status { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public AdminListResponse<AdminDeviceSummary> Data { get; private set; } = null!;
    public async Task OnGetAsync(CancellationToken ct) => Data = await data.DevicesAsync(PageNumber, ct, Search, Status);
}
public sealed class IncidentsModel(AdminDataSource data) : PageModel
{
    [BindProperty(SupportsGet = true)] public DateOnly? FromDate { get; set; }
    [BindProperty(SupportsGet = true)] public DateOnly? BeforeDate { get; set; }
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public string? Status { get; set; }
    [BindProperty(SupportsGet = true)] public string? Severity { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public AdminListResponse<AdminIncidentSummary> Data { get; private set; } = null!;
    public async Task OnGetAsync(CancellationToken ct) => Data = await data.IncidentsAsync(PageNumber, ct, Search, Status, Severity, FromDate, BeforeDate);
}
public sealed class AuditModel(AdminDataSource data) : PageModel
{
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public string? Result { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public AdminListResponse<AdminAuditSummary> Data { get; private set; } = null!;
    public async Task OnGetAsync(CancellationToken ct) => Data = await data.AuditAsync(PageNumber, ct, Search, Result);
}
