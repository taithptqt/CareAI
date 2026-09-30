using System.Security.Claims;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Controllers;

[ApiController, Authorize, Route("api/v1/elders/{elderId}/health")]
public sealed class HealthReportsController(CareAiDbContext db) : ControllerBase
{
    private Task<bool> Allowed(string elderId, CancellationToken ct)
    {
        var id = User.FindFirstValue(ClaimTypes.NameIdentifier);
        return db.ElderCaregivers.AnyAsync(ec => ec.ElderProfileId == elderId && ec.CaregiverId == id && ec.IsActive, ct);
    }

    [HttpGet("insights")]
    public async Task<IActionResult> Insights(string elderId, CancellationToken ct, long? beforeId = null)
    {
        if (!await Allowed(elderId, ct)) return Forbid();
        var rows = await db.HealthInsights.AsNoTracking()
            .Where(i => i.ElderProfileId == elderId && (!beforeId.HasValue || i.Id < beforeId.Value))
            .OrderByDescending(i => i.Id).Take(21).Select(i => new
            { i.Id, i.InsightType, i.WindowEndUtc, i.ObservedValue, i.BaselineValue }).ToListAsync(ct);
        return Ok(new { items = rows.Take(20), nextBeforeId = rows.Count > 20 ? (long?)rows[19].Id : null });
    }

    [HttpGet("weekly-reports")]
    public async Task<IActionResult> Reports(string elderId, CancellationToken ct, long? beforeId = null)
    {
        if (!await Allowed(elderId, ct)) return Forbid();
        var rows = await db.WeeklyHealthReports.AsNoTracking()
            .Where(r => r.ElderProfileId == elderId && (!beforeId.HasValue || r.Id < beforeId.Value))
            .OrderByDescending(r => r.Id).Take(21).Select(r => new
            { r.Id, r.WeekStartUtc, r.WeekEndUtc, r.Source, r.CreatedAt }).ToListAsync(ct);
        return Ok(new { items = rows.Take(20), nextBeforeId = rows.Count > 20 ? (long?)rows[19].Id : null });
    }

    [HttpGet("weekly-reports/{reportId:long}")]
    public async Task<IActionResult> Report(string elderId, long reportId, CancellationToken ct)
    {
        if (!await Allowed(elderId, ct)) return Forbid();
        var report = await db.WeeklyHealthReports.AsNoTracking()
            .Where(r => r.ElderProfileId == elderId && r.Id == reportId)
            .Select(r => new { r.Id, r.WeekStartUtc, r.WeekEndUtc, r.Source, r.Content, r.CreatedAt }).SingleOrDefaultAsync(ct);
        return report is null ? NotFound() : Ok(report);
    }
}
