using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class AuditDetailModel(AdminApiClient api) : PageModel
{
    public AdminAuditDetail Data { get; private set; } = null!;
    public string Changes
    {
        get
        {
            if (Data.ChangesJson is null) return "Sự kiện không có thay đổi trường nghiệp vụ.";
            using var document = System.Text.Json.JsonDocument.Parse(Data.ChangesJson);
            if (!document.RootElement.TryGetProperty("Fields", out var fields)) return Data.Action;
            return string.Join(", ", fields.EnumerateArray().Select(field => field.GetString() switch
            { "FullName" => "Họ tên", "PhoneNumber" => "Số điện thoại", "Role" => "Vai trò", "IsActive" => "Trạng thái hoạt động", "Reply" => "Nội dung trả lời", "Status" => "Trạng thái xử lý", _ => "Trường nghiệp vụ" }));
        }
    }
    public async Task OnGetAsync(string id, CancellationToken ct) => Data = await api.GetAsync<AdminAuditDetail>($"audit/{Uri.EscapeDataString(id)}", ct);
}
