using CareAI.Infrastructure.Admin;
using Microsoft.AspNetCore.DataProtection;

namespace CareAI.API.Admin;
public sealed class AdminMfaProtector(IDataProtectionProvider provider) : IAdminMfaProtector
{
    private readonly IDataProtector protector = provider.CreateProtector("CareAI.Admin.Mfa.v1");
    public string Protect(string value) => protector.Protect(value);
    public string Unprotect(string value) => protector.Unprotect(value);
}
