using CareAI.AdminWeb.Services;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

namespace CareAI.AdminWeb.Services;

public static class AdminWebExtensions
{
    public static IServiceCollection AddCareAiAdminWeb(
        this IServiceCollection services,
        IConfiguration configuration,
        IWebHostEnvironment environment)
    {
        services.AddRazorPages().AddMvcOptions(options =>
        {
            options.Filters.Add<AdminPageFilter>();
            options.Filters.Add<LoginAntiforgeryRecoveryFilter>();
        });

        services.AddScoped<AdminDataSource>();
        services.AddSingleton<AdminPreviewData>();
        services.AddSingleton<AdminWebMode>();
        services.AddHttpContextAccessor();
        services.AddScoped<AdminCookieEvents>();

        var mode = new AdminWebMode(environment, configuration);
        if (mode.Live)
        {
            var sessionConnection = configuration.GetConnectionString("AdminWebSessionStore")
                ?? configuration.GetConnectionString("DefaultConnection");
            var keyDirectory = configuration["AdminWeb:DataProtectionKeyDirectory"];
            if (string.IsNullOrWhiteSpace(keyDirectory))
            {
                keyDirectory = Path.Combine(environment.ContentRootPath, "keys");
            }

            try
            {
                Directory.CreateDirectory(keyDirectory);
            }
            catch
            {
                // Non-fatal if directory creation fails or running in constrained environment
            }

            if (string.IsNullOrWhiteSpace(sessionConnection))
            {
                services.AddDistributedMemoryCache();
            }
            else
            {
                services.AddDistributedSqlServerCache(options =>
                {
                    options.ConnectionString = sessionConnection;
                    options.SchemaName = "dbo";
                    options.TableName = "AdminWebTickets";
                });
            }

            var protection = services.AddDataProtection()
                .SetApplicationName("CareAI.AdminWeb")
                .PersistKeysToFileSystem(new DirectoryInfo(keyDirectory));

            var certificate = configuration["AdminWeb:KeyEncryptionCertificateThumbprint"];
            if (!string.IsNullOrWhiteSpace(certificate))
            {
                protection.ProtectKeysWithCertificate(certificate);
            }
            else if (environment.IsDevelopment() && OperatingSystem.IsWindows())
            {
                protection.ProtectKeysWithDpapi();
            }
        }
        else
        {
            services.AddDistributedMemoryCache();
        }

        services.AddSingleton<ProtectedTicketStore>();
        services.AddAuthentication().AddCookie("AdminCookie", options =>
        {
            options.Cookie.Name = "__Host-CareAI.Admin";
            options.Cookie.HttpOnly = true;
            options.Cookie.SecurePolicy = CookieSecurePolicy.Always;
            options.Cookie.SameSite = SameSiteMode.Lax;
            options.LoginPath = "/Login";
            options.AccessDeniedPath = "/Denied";
            options.ExpireTimeSpan = TimeSpan.FromHours(8);
            options.SlidingExpiration = false;
            options.EventsType = typeof(AdminCookieEvents);
        });

        services.AddOptions<CookieAuthenticationOptions>("AdminCookie")
            .Configure<ProtectedTicketStore>((options, store) => options.SessionStore = store);

        services.AddHttpClient<AdminApiClient>(client =>
        {
            if (mode.Live)
            {
                var baseUrl = configuration["AdminWeb:ApiBaseUrl"];
                if (string.IsNullOrWhiteSpace(baseUrl))
                {
                    baseUrl = environment.IsDevelopment() ? "https://localhost:7156" : "http://127.0.0.1:8080";
                }

                if (Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri))
                {
                    client.BaseAddress = new Uri(uri.AbsoluteUri.TrimEnd('/') + "/api/v1/admin/");
                }

                var webClientKey = configuration["AdminWeb:WebClientKey"]
                    ?? configuration["AdminSecurity:WebClientKey"]
                    ?? "CareAiAdminWebServiceClientSharedSecretKey2026Min32Bytes!";
                client.DefaultRequestHeaders.Add("X-CareAI-AdminWeb-Key", webClientKey);
            }
            client.Timeout = TimeSpan.FromSeconds(15);
        }).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });

        return services;
    }

    public static IApplicationBuilder UseCareAiAdminWeb(
        this IApplicationBuilder app,
        IConfiguration configuration,
        IWebHostEnvironment environment)
    {
        var mode = new AdminWebMode(environment, configuration);

        app.Use(async (context, next) =>
        {
            var path = context.Request.Path.Value ?? "";
            // Áp dụng bảo mật cho các route giao diện Web Admin
            if (path.StartsWith("/Accounts", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Devices", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Incidents", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Audit", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Feedback", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Manage", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Staff", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Security", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Login", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Logout", StringComparison.OrdinalIgnoreCase)
                || path.StartsWith("/Overview", StringComparison.OrdinalIgnoreCase))
            {
                context.Response.Headers.CacheControl = "no-store";
                context.Response.Headers["X-Content-Type-Options"] = "nosniff";
                context.Response.Headers["Referrer-Policy"] = "no-referrer";
                context.Response.Headers["Content-Security-Policy"] =
                    "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self'; " +
                    "img-src 'self' data:; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
            }

            await next();
        });

        app.Use(async (context, next) =>
        {
            var path = context.Request.Path;
            // Xác thực thủ công lược đồ AdminCookie cho toàn bộ các route Web Admin
            if (path == "/" || path.StartsWithSegments("/Login") || path.StartsWithSegments("/Error")
                || path.StartsWithSegments("/Denied") || path.StartsWithSegments("/Logout")
                || path.StartsWithSegments("/Accounts") || path.StartsWithSegments("/Devices")
                || path.StartsWithSegments("/Incidents") || path.StartsWithSegments("/Audit")
                || path.StartsWithSegments("/Feedback") || path.StartsWithSegments("/Manage")
                || path.StartsWithSegments("/Staff") || path.StartsWithSegments("/Security")
                || path.StartsWithSegments("/Overview"))
            {
                var authResult = await context.AuthenticateAsync("AdminCookie");
                if (authResult.Succeeded && authResult.Principal != null)
                {
                    context.User = authResult.Principal;
                }
            }

            if (path == "/")
            {
                context.Response.Redirect("/Login");
                return;
            }

            if (path == "/Login" || path == "/Error" || path == "/Denied" || path == "/Logout")
            {
                await next();
                return;
            }

            // Route web admin bảo vệ
            if (path.StartsWithSegments("/Accounts") || path.StartsWithSegments("/Devices")
                || path.StartsWithSegments("/Incidents") || path.StartsWithSegments("/Audit")
                || path.StartsWithSegments("/Feedback") || path.StartsWithSegments("/Manage")
                || path.StartsWithSegments("/Staff") || path.StartsWithSegments("/Security")
                || path.StartsWithSegments("/Overview"))
            {
                if (!mode.Preview && (!mode.Live || context.User.Identity?.IsAuthenticated != true))
                {
                    context.Response.Redirect("/Login");
                    return;
                }
            }

            await next();
        });

        return app;
    }
}
