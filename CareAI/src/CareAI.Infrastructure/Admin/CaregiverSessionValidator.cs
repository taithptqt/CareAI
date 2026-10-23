using System.Security.Claims;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;

namespace CareAI.Infrastructure.Admin;

public sealed record CaregiverCachedState(bool Exists, bool IsSuspended, int SecurityVersion)
{
    public static readonly CaregiverCachedState None = new(false, false, 0);
}

public static class CaregiverSessionValidator
{
    public static async Task<bool> IsValidAsync(
        CareAiDbContext db,
        ClaimsPrincipal user,
        CancellationToken ct,
        IMemoryCache? cache = null)
    {
        var id = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (id is null) return false;

        CaregiverCachedState? state = null;
        var cacheKey = $"auth:caregiver:{id}";

        if (cache != null && cache.TryGetValue(cacheKey, out CaregiverCachedState? cached) && cached != null)
        {
            state = cached;
        }
        else
        {
            var dbState = await db.Set<CaregiverAdminState>().AsNoTracking().SingleOrDefaultAsync(x => x.CaregiverId == id, ct);
            state = dbState is null
                ? CaregiverCachedState.None
                : new CaregiverCachedState(true, dbState.IsSuspended, dbState.SecurityVersion);

            cache?.Set(cacheKey, state, TimeSpan.FromSeconds(30));
        }

        if (!state.Exists) return true; // Existing tokens remain valid until an explicit revocation.
        if (state.IsSuspended) return false;
        return int.TryParse(user.FindFirst("csv")?.Value, out var version) ? version == state.SecurityVersion : state.SecurityVersion == 0;
    }
}
