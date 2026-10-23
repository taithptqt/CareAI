using System.ComponentModel.DataAnnotations;
using CareAI.AdminWeb.Services;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class SecurityModel(AdminApiClient api) : PageModel
{
    [BindProperty, Required, StringLength(256)] public string Password { get; set; } = "";
    [BindProperty, RegularExpression("^[0-9]{6}$")] public string? Code { get; set; }
    public string? Secret { get; private set; }
    public string? Message { get; private set; }
    public string? Error { get; private set; }
    public Task<IActionResult> OnPostBeginAsync(CancellationToken ct) => Enroll(null, ct);
    public Task<IActionResult> OnPostConfirmAsync(CancellationToken ct) => Enroll(Code ?? "invalid", ct);
    private async Task<IActionResult> Enroll(string? code, CancellationToken ct)
    {
        try
        {
            if (!ModelState.IsValid) return Page();
            var result = await api.PostAsync<AdminMfaEnrollment>("auth/mfa/enroll", new AdminMfaRequest { Password = Password, Code = code }, ct);
            Secret = result.Secret;
            Message = result.Enabled ? "Đã bật MFA. Khi đăng nhập lại, dùng mã TOTP mới; mã vừa xác nhận không được dùng lại." : "Thêm khóa thủ công vào ứng dụng xác thực TOTP, sau đó nhập mã 6 chữ số để xác nhận.";
            return Page();
        }
        catch (AdminApiException error) when (error.StatusCode is 400 or 403 or 409 or 429)
        { Error = error.UserMessage ?? "Không hoàn tất thiết lập. Kiểm tra mật khẩu và mã TOTP rồi thử lại."; return Page(); }
        finally { Password = ""; ModelState.Remove(nameof(Password)); Code = null; ModelState.Remove(nameof(Code)); }
    }
}
