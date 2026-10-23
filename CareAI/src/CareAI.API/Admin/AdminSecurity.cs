using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using CareAI.Core.DTOs.Admin;
using CareAI.Core.Entities.Admin;
using CareAI.Infrastructure.Admin;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.AspNetCore.DataProtection;

namespace CareAI.API.Admin;

public sealed class AdminSecurityOptions
{
    public bool Enabled { get; set; }
    public string Issuer { get; set; } = "CareAI.Admin";
    public string Audience { get; set; } = "CareAI.AdminWeb";
    public string SigningKey { get; set; } = "";
    public string WebClientKey { get; set; } = "";
    public string? DisabledReason { get; set; }
    public bool RequireMfa { get; set; }
}

public static class AdminSecurity
{
    public const string Scheme = "AdminBearer";
    public static IServiceCollection AddCareAiAdmin(this IServiceCollection services, IConfiguration configuration, IWebHostEnvironment environment)
    {
        var settings = configuration.GetSection("AdminSecurity").Get<AdminSecurityOptions>() ?? new();
        var keyDirectory = configuration["AdminSecurity:DataProtectionKeyDirectory"];
        var certificate = configuration["AdminSecurity:KeyEncryptionCertificateThumbprint"];
        var productionReady = configuration.GetValue<bool>("AdminSecurity:ProductionReady", true)
            || (settings.RequireMfa && !string.IsNullOrWhiteSpace(keyDirectory) && !string.IsNullOrWhiteSpace(certificate));
        if (settings.Enabled && ((!environment.IsDevelopment() && !productionReady) || Encoding.UTF8.GetByteCount(settings.SigningKey) < 32
            || Encoding.UTF8.GetByteCount(settings.WebClientKey) < 32 || settings.WebClientKey == settings.SigningKey
            || settings.SigningKey == configuration["Jwt:SecretKey"]
            || settings.Issuer == (configuration["Jwt:Issuer"] ?? "CareAI.Server")
            || settings.Audience == (configuration["Jwt:Audience"] ?? "CareAI.CaregiverApp")))
        {
            // A broken admin configuration must not take telemetry/SOS offline.
            settings.Enabled = false;
            settings.DisabledReason = "Admin disabled: requires separate issuer/audience and separate signing/client keys of at least 32 bytes; Production also requires MFA and persistent certificate-protected Data Protection keys.";
        }
        var protection = services.AddDataProtection().SetApplicationName("CareAI.AdminApi");
        if (!string.IsNullOrWhiteSpace(keyDirectory)) protection.PersistKeysToFileSystem(new DirectoryInfo(keyDirectory));
        if (!environment.IsDevelopment() && settings.Enabled && !string.IsNullOrWhiteSpace(certificate))
        {
            try { protection.ProtectKeysWithCertificate(certificate); }
            catch (Exception error) when (error is System.Security.Cryptography.CryptographicException or ArgumentException)
            { settings.Enabled = false; settings.DisabledReason = "Admin disabled: key encryption certificate could not be loaded."; }
        }
        else if (OperatingSystem.IsWindows()) protection.ProtectKeysWithDpapi();
        services.AddSingleton(settings);
        services.AddSingleton(new AdminMfaOptions(settings.RequireMfa));
        services.AddSingleton<IAdminMfaProtector, AdminMfaProtector>();
        services.AddScoped<AdminMfaService>();
        services.AddScoped<AdminAuthService>();
        services.AddScoped<AdminReadService>();
        services.AddScoped<AdminOperationsReadService>();
        services.AddScoped<AdminCommandService>();
        services.AddSingleton(new AdminCommandOptions(settings.WebClientKey, configuration.GetValue<bool>("AdminSecurity:CaregiverApiEnforcementReady")));
        services.AddAuthentication().AddJwtBearer(Scheme, options =>
        {
            options.MapInboundClaims = false;
            options.TokenValidationParameters = new()
            {
                ValidateIssuer = true, ValidIssuer = settings.Issuer,
                ValidateAudience = true, ValidAudience = settings.Audience,
                ValidateLifetime = true, ValidateIssuerSigningKey = true, ClockSkew = TimeSpan.Zero,
                ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                IssuerSigningKey = settings.Enabled ? new SymmetricSecurityKey(Encoding.UTF8.GetBytes(settings.SigningKey)) : null,
                NameClaimType = "name", RoleClaimType = "admin_role"
            };
            options.Events = new JwtBearerEvents
            {
                OnMessageReceived = context =>
                {
                    if (!settings.Enabled) context.Fail("Admin disabled.");
                    return Task.CompletedTask;
                },
                OnTokenValidated = async context =>
                {
                    var principal = context.Principal!;
                    var id = principal.FindFirst("sub")?.Value;
                    var sessionId = principal.FindFirst("sid")?.Value;
                    if (id is null || sessionId is null || !int.TryParse(principal.FindFirst("sv")?.Value, out var version))
                    { context.Fail("Invalid admin session."); return; }
                    var validated = await context.HttpContext.RequestServices.GetRequiredService<AdminAuthService>()
                        .ValidateSessionAsync(id, sessionId, version, context.HttpContext.RequestAborted);
                    if (validated is null) { context.Fail("Admin session revoked or expired."); return; }
                    var (user, enrollmentOnly) = validated.Value;
                    if (settings.RequireMfa && !user.MfaEnabled && !enrollmentOnly) { context.Fail("MFA enrollment required."); return; }
                    // Rebuild permissions from current server state, never trust stale permission claims.
                    var claims = new List<Claim> { new("sub", user.Id), new("sid", sessionId), new("name", user.FullName), new("admin_role", user.Role) };
                    if (!enrollmentOnly) claims.AddRange(AdminPermissions.ForRole(user.Role).Select(p => new Claim("admin_permission", p)));
                    context.Principal = new ClaimsPrincipal(new ClaimsIdentity(claims, Scheme, "name", "admin_role"));
                }
            };
        });
        services.AddAuthorization(options =>
        {
            foreach (var permission in AdminPermissions.All)
                options.AddPolicy(permission, policy => policy.AddAuthenticationSchemes(Scheme).RequireAuthenticatedUser().RequireClaim("admin_permission", permission));
        });
        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.AddPolicy("admin-mfa", context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions
                { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
            options.AddPolicy("admin-command", context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions
                { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
            options.AddPolicy("admin-login", context => RateLimitPartition.GetFixedWindowLimiter(
                context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions
                { PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
        });
        return services;
    }

    public static string IssueToken(AdminUser user, AdminSession session, AdminSecurityOptions options) =>
        new JwtSecurityTokenHandler().WriteToken(new JwtSecurityToken(options.Issuer, options.Audience,
            [new("sub", user.Id), new("sid", session.Id), new("sv", user.SecurityVersion.ToString(System.Globalization.CultureInfo.InvariantCulture))],
            notBefore: DateTime.UtcNow, expires: session.ExpiresAtUtc,
            signingCredentials: new(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(options.SigningKey)), SecurityAlgorithms.HmacSha256)));
}
