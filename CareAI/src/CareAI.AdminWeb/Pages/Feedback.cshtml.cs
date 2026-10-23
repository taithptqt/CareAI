using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class FeedbackModel(AdminDataSource data) : PageModel
{
    [BindProperty(SupportsGet = true)] public string? Search { get; set; }
    [BindProperty(SupportsGet = true)] public string? Category { get; set; }
    [BindProperty(SupportsGet = true)] public int PageNumber { get; set; } = 1;
    public AdminListResponse<AdminFeedbackDto> Data { get; private set; } = null!;
    public async Task<IActionResult> OnGetAsync(CancellationToken ct)
    {
        if ((Search?.Length ?? 0) > 120 || Category is not (null or "" or "Bug" or "Suggestion" or "Other")) return BadRequest("Bộ lọc không hợp lệ.");
        Search = Search?.Trim();
        Data = await data.FeedbackAsync(Search, Category, PageNumber, ct);
        PageNumber = Data.Page;
        return Page();
    }
    public static string CategoryLabel(string category) => category switch
    { "Bug" => "Báo lỗi", "Suggestion" => "Đề xuất cải tiến", _ => "Góp ý khác" };
}
