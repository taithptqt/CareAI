using System.ComponentModel.DataAnnotations;
using CareAI.API.Admin;
using CareAI.Core.DTOs.Admin;
using CareAI.Infrastructure.Feedback;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CareAI.API.Controllers.Admin;

[ApiController]
[Route("api/v1/admin/feedback")]
[Authorize(AuthenticationSchemes = AdminSecurity.Scheme, Policy = AdminPermissions.Feedback)]
public sealed class AdminFeedbackController(FeedbackService feedback) : ControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Inbox([FromQuery, MaxLength(120)] string? search,
        [FromQuery, RegularExpression("^(Bug|Suggestion|Other)?$")] string? category,
        [FromQuery, Range(1, int.MaxValue)] int page = 1, CancellationToken ct = default)
    {
        Response.Headers.CacheControl = "no-store";
        return Ok(await feedback.InboxAsync(search?.Trim(), string.IsNullOrWhiteSpace(category) ? null : category, page, ct));
    }
}
