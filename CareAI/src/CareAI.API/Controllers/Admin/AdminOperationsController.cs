using System.ComponentModel.DataAnnotations;
using CareAI.API.Admin;
using CareAI.Core.DTOs.Admin;
using CareAI.Infrastructure.Admin;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace CareAI.API.Controllers.Admin;

[ApiController, Route("api/v1/admin/operations")]
[Authorize(AuthenticationSchemes = AdminSecurity.Scheme)]
public sealed class AdminOperationsController(AdminOperationsReadService reads, AdminCommandService commands, CareAI.Infrastructure.Data.CareAiDbContext db) : ControllerBase
{
    [HttpGet("{kind}")]
    public async Task<IActionResult> List(string kind, [FromQuery, MaxLength(120)] string? search,
        [FromQuery, Range(1, int.MaxValue)] int page = 1, CancellationToken ct = default)
    {
        var permission = kind switch { "staff" => AdminPermissions.Staff, "elders" => AdminPermissions.Elders, "care-links" => AdminPermissions.CareLinks, _ => null };
        if (permission is null) return NotFound();
        if (!User.HasClaim("admin_permission", permission)) return Forbid(AdminSecurity.Scheme);
        return Ok(await reads.ListAsync(kind, search?.Trim(), page, ct));
    }
    [HttpGet("{kind}/{id}")]
    public async Task<IActionResult> Record(string kind, string id, CancellationToken ct)
    {
        var permission = kind == "staff" ? AdminPermissions.Staff : kind == "elders" ? AdminPermissions.Elders : AdminPermissions.Manage;
        if (!User.HasClaim("admin_permission", permission)) return Forbid(AdminSecurity.Scheme);
        var record = await reads.RecordAsync(kind, id, ct);
        return record is null ? NotFound() : Ok(record);
    }
    [HttpGet("incident/{id}/timeline"), Authorize(Policy = AdminPermissions.Incidents)]
    public async Task<IActionResult> Incident(string id, CancellationToken ct)
    {
        var result = await reads.IncidentAsync(id, ct);
        return result is null ? NotFound() : Ok(result);
    }
    [HttpPost("command"), EnableRateLimiting("admin-command"), RequestSizeLimit(32_768)]
    public async Task<IActionResult> Command(AdminCommandRequest request, CancellationToken ct)
    {
        try { return Ok(await commands.ExecuteAsync(User.FindFirst("sub")!.Value, User.FindFirst("sid")!.Value, request, HttpContext.TraceIdentifier, ct)); }
        catch (AdminBusinessException)
        {
            db.ChangeTracker.Clear();
            db.Set<CareAI.Core.Entities.Admin.AdminAuditEvent>().Add(new()
            {
                ActorId = User.FindFirst("sub")!.Value, Action = request.Action, TargetId = request.TargetId,
                Reason = request.Reason.Trim(), Result = "Denied", TraceId = HttpContext.TraceIdentifier
            });
            await db.SaveChangesAsync(ct);
            throw;
        }
    }
}
