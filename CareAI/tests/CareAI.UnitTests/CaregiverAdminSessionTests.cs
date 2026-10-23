using System.Security.Claims;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Admin;
using CareAI.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace CareAI.UnitTests;
public sealed class CaregiverAdminSessionTests
{
    [Theory]
    [InlineData(false, 0, null, true)]
    [InlineData(false, 1, null, false)]
    [InlineData(false, 2, "1", false)]
    [InlineData(false, 2, "2", true)]
    [InlineData(true, 2, "2", false)]
    public async Task RevocationCutoverPreservesOnlyMatchingNonSuspendedSessions(bool suspended, int version, string? tokenVersion, bool expected)
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Set<CaregiverAdminState>().Add(new() { CaregiverId = "fictional", IsSuspended = suspended, SecurityVersion = version });
        await db.SaveChangesAsync();
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, "fictional") };
        if (tokenVersion is not null) claims.Add(new("csv", tokenVersion));
        Assert.Equal(expected, await CaregiverSessionValidator.IsValidAsync(db, new(new ClaimsIdentity(claims, "test")), default));
    }
    [Fact]
    public async Task UnrevokedLegacyAccountRemainsValid()
    {
        await using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var user = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "fictional")], "test"));
        Assert.True(await CaregiverSessionValidator.IsValidAsync(db, user, default));
    }
}
