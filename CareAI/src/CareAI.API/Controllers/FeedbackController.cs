using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using CareAI.Core.DTOs;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Feedback;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Controllers;

[ApiController]
[Route("api/v1/caregivers/feedback")]
[Authorize(AuthenticationSchemes = JwtBearerDefaults.AuthenticationScheme, Roles = "Caregiver")]
public sealed class FeedbackController(FeedbackService feedback, CareAiDbContext db) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Mine([FromQuery, Range(1, int.MaxValue)] int page = 1, CancellationToken ct = default)
    {
        var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (id is null || !await db.Caregivers.AnyAsync(x => x.Id == id, ct)) return Unauthorized();
        if (await db.Set<CareAI.Core.Entities.Admin.CaregiverAdminState>().AnyAsync(s => s.CaregiverId == id && s.IsSuspended, ct))
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Tài khoản của bạn đang bị tạm ngưng hoạt động." });
        Response.Headers.CacheControl = "no-store";
        return Ok(await feedback.MineAsync(id, page, ct));
    }

    [HttpPost, RequestSizeLimit(16_384)]
    public async Task<IActionResult> Submit(SubmitFeedbackRequest request, CancellationToken ct)
    {
        var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (id is null || !await db.Caregivers.AnyAsync(x => x.Id == id, ct)) return Unauthorized();
        if (await db.Set<CareAI.Core.Entities.Admin.CaregiverAdminState>().AnyAsync(s => s.CaregiverId == id && s.IsSuspended, ct))
            return StatusCode(StatusCodes.Status403Forbidden, new { error = "Tài khoản của bạn đang bị tạm ngưng hoạt động." });
        if (request.Subject.Trim().Length < 3 || request.Message.Trim().Length < 10)
            return Problem(statusCode: 400, title: "Tiêu đề cần ít nhất 3 ký tự và nội dung cần ít nhất 10 ký tự sau khi bỏ khoảng trắng.");
        if (request.Subject.Trim().Length > 120 || request.Message.Trim().Length > 3000)
            return Problem(statusCode: 400, title: "Tiêu đề không được vượt quá 120 ký tự và nội dung không được vượt quá 3000 ký tự.");
        Response.Headers.CacheControl = "no-store";
        try { return Ok(await feedback.SubmitAsync(id, request, ct)); }
        catch (FeedbackConflictException) { return Problem(statusCode: 409, title: "Mã gửi đã được dùng cho nội dung khác."); }
        catch (FeedbackRateLimitException) { return Problem(statusCode: 429, title: "Bạn đã gửi 10 phản hồi trong một giờ. Vui lòng thử lại sau."); }
    }
}
