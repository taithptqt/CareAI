using System.Security.Claims;
using CareAI.Infrastructure.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Controllers;

// Raw measurements only: the existing dashboard chart supplies synthetic points
// when history is empty, which must not be presented as HealthKit readings.
[ApiController]
[Authorize]
[Route("api/v1/elders/{elderProfileId}/vitals")]
public sealed class VitalsController(CareAiDbContext db) : ControllerBase
{
    [HttpGet("recent")]
    public async Task<IActionResult> GetRecent(string elderProfileId, CancellationToken ct)
    {
        var caregiverId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(caregiverId)) return Unauthorized();

        var allowed = await db.ElderCaregivers.AsNoTracking().AnyAsync(
            relation => relation.CaregiverId == caregiverId &&
                        relation.ElderProfileId == elderProfileId && relation.IsActive, ct);
        if (!allowed) return Forbid();

        var since = DateTime.UtcNow.AddHours(-24);
        var measurements = await db.HealthMeasurements.AsNoTracking()
            .Where(sample => sample.ElderProfileId == elderProfileId &&
                             (sample.MetricType == "HEART_RATE" || sample.MetricType == "SPO2") &&
                             sample.Timestamp >= since)
            .OrderByDescending(sample => sample.Timestamp)
            .Take(500)
            .Select(sample => new
            {
                sample.MetricType,
                sample.Value,
                sample.Unit,
                sample.Timestamp
            })
            .ToListAsync(ct);

        return Ok(measurements);
    }
}
