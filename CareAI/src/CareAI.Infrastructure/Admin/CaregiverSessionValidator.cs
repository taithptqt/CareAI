using System.Security.Claims;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.Infrastructure.Admin;

public static class CaregiverSessionValidator
{
    public static async Task<bool> IsValidAsync(CareAiDbContext db, ClaimsPrincipal user, CancellationToken ct)
    {
        var id = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (id is null) return false;
        var state = await db.Set<CaregiverAdminState>().AsNoTracking().SingleOrDefaultAsync(x => x.CaregiverId == id, ct);
        if (state is null) return true; // Existing tokens remain valid until an explicit revocation.
        if (state.IsSuspended) return false;
        return int.TryParse(user.FindFirst("csv")?.Value, out var version) ? version == state.SecurityVersion : state.SecurityVersion == 0;
    }
}
