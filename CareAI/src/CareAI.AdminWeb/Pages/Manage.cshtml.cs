using System.ComponentModel.DataAnnotations;
using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class ManageModel(AdminApiClient api, AdminWebMode mode) : PageModel
{
    [BindProperty(SupportsGet = true)] public string Kind { get; set; } = "";
    [BindProperty(SupportsGet = true)] public string Id { get; set; } = "";
    [BindProperty] public string RequestId { get; set; } = Guid.NewGuid().ToString();
    [BindProperty] public string ExpectedVersion { get; set; } = "";
    [BindProperty] public string Action { get; set; } = "";
    [BindProperty, Required, StringLength(500, MinimumLength = 5)] public string Reason { get; set; } = "";
    [BindProperty, Required, StringLength(256)] public string ReauthPassword { get; set; } = "";
    [BindProperty] public Dictionary<string, string> Values { get; set; } = [];
    public AdminRecord Record { get; private set; } = null!;
    public string? Error { get; private set; }
    [TempData] public string? Success { get; set; }
    public string BackPage => Kind switch { "staff" => "/Staff", "elders" => "/Elders", "care-links" => "/CareLinks", "feedback" => "/Feedback", "devices" => "/Devices", _ => "/Accounts/Index" };
    public string Existing(string label) => Record.Fields.FirstOrDefault(f => f.Label == label)?.Value ?? "";
    public string Input(string key, string fallback = "") => Values.GetValueOrDefault(key) ?? fallback;
    private Task<AdminRecord> Load(CancellationToken ct) => api.GetAsync<AdminRecord>($"operations/{Uri.EscapeDataString(Kind)}/{Uri.EscapeDataString(Id)}", ct);
    public async Task<IActionResult> OnGetAsync(CancellationToken ct)
    {
        if (mode.Preview) return RedirectToPage("/Overview");
        Record = await Load(ct); ExpectedVersion = Record.Version;
        return Page();
    }
    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!mode.Live || Kind == "elders") return Forbid();
        Record = await Load(ct);
        var allowed = Kind switch
        {
            "accounts" => new[] { "account.update", "account.unlock", "account.suspend", "account.restore", "account.revoke" }, "devices" => ["device.revoke"],
            "care-links" => ["link.primary", "link.deactivate"], "staff" => Id == "new" ? ["staff.create"] : ["staff.update", "staff.revoke"],
            "feedback" => ["feedback.reply"], _ => []
        };
        if (!allowed.Contains(Action)) return BadRequest();
        try
        {
            if (!ModelState.IsValid) return Page();
            var result = await api.PostAsync<AdminCommandResult>("operations/command", new AdminCommandRequest
            {
                RequestId = RequestId, Action = Action, TargetId = Id, ExpectedVersion = ExpectedVersion,
                Reason = Reason, ReauthPassword = ReauthPassword, Values = Values
            }, ct);
            Success = result.Message;
            return RedirectToPage("/Manage", new { kind = Kind, id = result.TargetId });
        }
        catch (AdminApiException error) when (error.StatusCode is 400 or 403 or 409 or 429 or 503)
        {
            Error = error.UserMessage ?? (error.StatusCode == 429 ? "Thao tác quá nhanh. Chờ một phút rồi thử lại." : $"Không hoàn tất được thay đổi. Mã đối chiếu: {error.TraceId}");
            return Page();
        }
        finally
        {
            ReauthPassword = ""; ModelState.Remove(nameof(ReauthPassword));
            Values.Remove("NewPassword"); ModelState.Remove("Values[NewPassword]");
        }
    }
}
