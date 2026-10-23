using CareAI.Core.DTOs.Admin;
using CareAI.Core.DTOs;

namespace CareAI.AdminWeb.Services;

public sealed class AdminDataSource(AdminWebMode mode, AdminPreviewData preview, AdminApiClient api)
{
    public Task<AdminListResponse<AdminFeedbackDto>> FeedbackAsync(string? search, string? category, int page, CancellationToken ct) => mode.Preview
        ? Task.FromResult(Paginate<AdminFeedbackDto>([], page))
        : api.GetAsync<AdminListResponse<AdminFeedbackDto>>($"feedback?search={Uri.EscapeDataString(search ?? "")}&category={Uri.EscapeDataString(category ?? "")}&page={Math.Max(1, page)}", ct);
    public Task<AdminOverviewResponse> OverviewAsync(CancellationToken ct) => mode.Preview
        ? Task.FromResult(preview.Overview) : api.GetAsync<AdminOverviewResponse>("overview", ct);
    public Task<AdminAccountSummary?> AccountAsync(string id, CancellationToken ct) => mode.Preview
        ? Task.FromResult(preview.Accounts.SingleOrDefault(x => x.Id == id))
        : api.GetAsync<AdminAccountSummary?>("accounts/" + Uri.EscapeDataString(id), ct);
    public Task<AdminListResponse<AdminAccountSummary>> AccountsAsync(string? search, string? status, bool locked, int page, CancellationToken ct)
    {
        if (!mode.Preview) return api.GetAsync<AdminListResponse<AdminAccountSummary>>(
            $"accounts?search={Uri.EscapeDataString(search ?? "")}&status={Escape(status)}&locked={locked.ToString().ToLowerInvariant()}&page={Math.Max(1, page)}&pageSize=25", ct);
        var query = preview.Accounts.AsEnumerable();
        if (!string.IsNullOrWhiteSpace(search)) query = query.Where(x => x.FullName.Contains(search, StringComparison.OrdinalIgnoreCase) || x.MaskedEmail.Contains(search, StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrEmpty(status)) query = query.Where(x => x.AdministrativeStatus == status);
        if (locked) query = query.Where(x => x.LockoutEndUtc > preview.AsOfUtc);
        return Task.FromResult(Paginate(query.OrderByDescending(x => x.CreatedAt).ThenBy(x => x.Id).ToArray(), page));
    }
    public Task<AdminListResponse<AdminDeviceSummary>> DevicesAsync(int page, CancellationToken ct, string? search = null, string? status = null) => mode.Preview
        ? Task.FromResult(Paginate(preview.Devices, page)) : api.GetAsync<AdminListResponse<AdminDeviceSummary>>($"devices?page={Math.Max(1, page)}&search={Escape(search)}&status={Escape(status)}", ct);
    public Task<AdminListResponse<AdminIncidentSummary>> IncidentsAsync(int page, CancellationToken ct, string? search = null, string? status = null, string? severity = null, DateOnly? from = null, DateOnly? before = null) => mode.Preview
        ? Task.FromResult(Paginate(preview.Incidents, page)) : api.GetAsync<AdminListResponse<AdminIncidentSummary>>($"incidents?page={Math.Max(1, page)}&search={Escape(search)}&status={Escape(status)}&severity={Escape(severity)}&from={Day(from)}&before={Day(before)}", ct);
    public Task<AdminListResponse<AdminAuditSummary>> AuditAsync(int page, CancellationToken ct, string? search = null, string? result = null) => mode.Preview
        ? Task.FromResult(Paginate<AdminAuditSummary>([], page)) : api.GetAsync<AdminListResponse<AdminAuditSummary>>($"audit?page={Math.Max(1, page)}&search={Escape(search)}&result={Escape(result)}", ct);
    private static string Escape(string? text) => Uri.EscapeDataString(text ?? "");
    private static string Day(DateOnly? day) => day is null ? "" : Escape(new DateTimeOffset(day.Value.ToDateTime(TimeOnly.MinValue), TimeSpan.FromHours(7)).UtcDateTime.ToString("O", System.Globalization.CultureInfo.InvariantCulture));
    private AdminListResponse<T> Paginate<T>(IReadOnlyList<T> items, int page)
    {
        page = Math.Clamp(page, 1, Math.Max(1, (int)Math.Ceiling(items.Count / 25d)));
        return new(items.Skip((page - 1) * 25).Take(25).ToArray(), items.Count, page, 25, preview.AsOfUtc);
    }
}
