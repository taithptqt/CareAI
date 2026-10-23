using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Extensions.Caching.Distributed;

namespace CareAI.AdminWeb.Services;

// The browser cookie contains only the middleware's protected session reference.
// Bearer tokens inside tickets are encrypted before writing to the shared SQL cache.
public sealed class ProtectedTicketStore(IDistributedCache cache, IDataProtectionProvider protection) : ITicketStore
{
    private readonly IDataProtector protector = protection.CreateProtector("CareAI.AdminWeb.Tickets.v1");
    public async Task<string> StoreAsync(AuthenticationTicket ticket)
    {
        var key = "admin-ticket:" + Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        await RenewAsync(key, ticket);
        return key;
    }
    public Task RenewAsync(string key, AuthenticationTicket ticket) => cache.SetAsync(key,
        protector.Protect(TicketSerializer.Default.Serialize(ticket)), new DistributedCacheEntryOptions
        { AbsoluteExpiration = ticket.Properties.ExpiresUtc, SlidingExpiration = TimeSpan.FromMinutes(30) });
    public async Task<AuthenticationTicket?> RetrieveAsync(string key)
    {
        var value = await cache.GetAsync(key);
        if (value is null) return null;
        try { return TicketSerializer.Default.Deserialize(protector.Unprotect(value)); }
        catch (CryptographicException) { await cache.RemoveAsync(key); return null; }
    }
    public Task RemoveAsync(string key) => cache.RemoveAsync(key);
}
