using System.ComponentModel.DataAnnotations;
using CareAI.API.Admin;
using CareAI.Core.DTOs.Admin;
using CareAI.Infrastructure.Admin;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace CareAI.API.Controllers.Admin;

[ApiController]
[Route("api/v1/admin")]
[Authorize(AuthenticationSchemes = AdminSecurity.Scheme)]
public sealed class AdminReadController(AdminReadService reads) : ControllerBase
{
    [HttpGet("audit/{id}"), Authorize(Policy = AdminPermissions.Audit)]
    public async Task<IActionResult> AuditDetail(string id, CancellationToken ct)
    {
        var result = await reads.AuditDetailAsync(id, ct);
        return result is null ? NotFound() : Ok(result);
    }
    [HttpGet("overview"), Authorize(Policy = AdminPermissions.Overview)]
    public async Task<IActionResult> Overview(CancellationToken ct) => Ok(await reads.OverviewAsync(ct));

    [HttpGet("accounts"), Authorize(Policy = AdminPermissions.Accounts)]
    public async Task<IActionResult> Accounts([FromQuery, MaxLength(120)] string? search, [FromQuery] bool locked = false,
        [FromQuery, Range(1, int.MaxValue)] int page = 1, [FromQuery, Range(1, 100)] int pageSize = 25,
        [FromQuery, RegularExpression("^(Active|Suspended)$")] string? status = null, CancellationToken ct = default)
        => Ok(await reads.AccountsAsync(search?.Trim(), locked, page, pageSize, ct, status));

    [HttpGet("accounts/{id}"), Authorize(Policy = AdminPermissions.Accounts)]
    public async Task<IActionResult> Account(string id, CancellationToken ct)
    {
        var account = await reads.AccountAsync(id, ct);
        return account is null ? NotFound() : Ok(account);
    }

    [HttpGet("devices"), Authorize(Policy = AdminPermissions.Devices)]
    public async Task<IActionResult> Devices([FromQuery, Range(1, int.MaxValue)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 25, [FromQuery, MaxLength(120)] string? search = null,
        [FromQuery, RegularExpression("^(Online|Offline|Unknown|Revoked)$")] string? status = null, CancellationToken ct = default)
        => Ok(await reads.DevicesAsync(page, pageSize, ct, search, status));

    [HttpGet("incidents"), Authorize(Policy = AdminPermissions.Incidents)]
    public async Task<IActionResult> Incidents([FromQuery, Range(1, int.MaxValue)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 25, [FromQuery, MaxLength(120)] string? search = null,
        [FromQuery, RegularExpression("^(Open|Acknowledged|Resolved)$")] string? status = null,
        [FromQuery, RegularExpression("^(Low|Medium|High|Critical)$")] string? severity = null,
        [FromQuery] DateTimeOffset? from = null, [FromQuery] DateTimeOffset? before = null, CancellationToken ct = default)
    {
        if (from is not null && before is not null && (before <= from || before - from > TimeSpan.FromDays(90))) return BadRequest();
        return Ok(await reads.IncidentsAsync(page, pageSize, ct, search,
            Enum.TryParse<CareAI.Core.Enums.IncidentStatus>(status, out var state) ? state : null,
            Enum.TryParse<CareAI.Core.Enums.IncidentSeverity>(severity, out var level) ? level : null,
            from?.UtcDateTime, before?.UtcDateTime));
    }

    [HttpGet("audit"), Authorize(Policy = AdminPermissions.Audit)]
    public async Task<IActionResult> Audit([FromQuery, Range(1, int.MaxValue)] int page = 1,
        [FromQuery, Range(1, 100)] int pageSize = 25, [FromQuery, MaxLength(120)] string? search = null,
        [FromQuery, RegularExpression("^(Success|Denied)$")] string? result = null, CancellationToken ct = default)
        => Ok(await reads.AuditAsync(page, pageSize, ct, search, result));
}
