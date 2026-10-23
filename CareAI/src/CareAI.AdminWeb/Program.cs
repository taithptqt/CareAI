using CareAI.AdminWeb.Services;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages().AddMvcOptions(options =>
{
    options.Filters.Add<AdminPageFilter>();
    options.Filters.Add<LoginAntiforgeryRecoveryFilter>();
});
builder.Services.AddScoped<AdminDataSource>();
builder.Services.AddSingleton<AdminPreviewData>();
builder.Services.AddSingleton<AdminWebMode>();
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<AdminCookieEvents>();
var mode = new AdminWebMode(builder.Environment, builder.Configuration);
if (mode.Live)
{
    var sessionConnection = builder.Configuration.GetConnectionString("AdminWebSessionStore");
    var keyDirectory = builder.Configuration["AdminWeb:DataProtectionKeyDirectory"];
    if (string.IsNullOrWhiteSpace(keyDirectory))
    {
        keyDirectory = builder.Environment.IsDevelopment()
            ? Path.Combine(builder.Environment.ContentRootPath, "keys")
            : throw new InvalidOperationException("Live admin requires a protected Data Protection key directory.");
    }
    if (string.IsNullOrWhiteSpace(sessionConnection))
    {
        if (builder.Environment.IsDevelopment())
        {
            builder.Services.AddDistributedMemoryCache();
        }
        else
        {
            throw new InvalidOperationException("Live admin requires an explicit SQL session store in production.");
        }
    }
    else
    {
        builder.Services.AddDistributedSqlServerCache(options =>
        {
            options.ConnectionString = sessionConnection;
            options.SchemaName = "dbo";
            options.TableName = "AdminWebTickets";
        });
    }
    var protection = builder.Services.AddDataProtection().SetApplicationName("CareAI.AdminWeb")
        .PersistKeysToFileSystem(new DirectoryInfo(keyDirectory));
    if (!builder.Environment.IsDevelopment())
    {
        var certificate = builder.Configuration["AdminWeb:KeyEncryptionCertificateThumbprint"];
        if (string.IsNullOrWhiteSpace(certificate)) throw new InvalidOperationException("Production admin web requires a Data Protection key encryption certificate.");
        protection.ProtectKeysWithCertificate(certificate);
    }
    else if (OperatingSystem.IsWindows()) protection.ProtectKeysWithDpapi();
}
else builder.Services.AddDistributedMemoryCache(); // Preview has no authenticated tickets.
builder.Services.AddSingleton<ProtectedTicketStore>();
builder.Services.AddAuthentication("AdminCookie").AddCookie("AdminCookie", options =>
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
builder.Services.AddOptions<CookieAuthenticationOptions>("AdminCookie")
    .Configure<ProtectedTicketStore>((options, store) => options.SessionStore = store);
builder.Services.AddAuthorization();
builder.Services.AddHttpClient<AdminApiClient>(client =>
{
    if (mode.Live)
    {
        if (!Uri.TryCreate(builder.Configuration["AdminWeb:ApiBaseUrl"], UriKind.Absolute, out var uri)
            || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo) || !string.IsNullOrEmpty(uri.Query)
            || !string.IsNullOrEmpty(uri.Fragment))
            throw new InvalidOperationException("AdminWeb:ApiBaseUrl must be an HTTPS URL without credentials, query or fragment.");
        client.BaseAddress = new Uri(uri.AbsoluteUri.TrimEnd('/') + "/api/v1/admin/");
        var webClientKey = builder.Configuration["AdminWeb:WebClientKey"];
        if (string.IsNullOrWhiteSpace(webClientKey) || System.Text.Encoding.UTF8.GetByteCount(webClientKey) < 32)
            throw new InvalidOperationException("AdminWeb:WebClientKey must match the API server-to-server key (at least 32 bytes).");
        client.DefaultRequestHeaders.Add("X-CareAI-AdminWeb-Key", webClientKey);
    }
    client.Timeout = TimeSpan.FromSeconds(15);
}).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false });

var app = builder.Build();
app.UseExceptionHandler("/Error");
if (!app.Environment.IsDevelopment()) app.UseHsts();
app.UseHttpsRedirection();
app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; " +
        "img-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";

    await next();
});
app.UseStaticFiles();
app.UseRouting();
app.UseWhen(context => mode.Live && context.Request.Path != "/Error", branch =>
{
    branch.UseAuthentication();
    branch.UseAuthorization();
});
app.Use(async (context, next) =>
{
    var path = context.Request.Path;
    if (path == "/Login" || path == "/Error" || path == "/Denied") { await next(); return; }
    if (!mode.Preview && (!mode.Live || context.User.Identity?.IsAuthenticated != true))
    { context.Response.Redirect("/Login"); return; }
    await next();
});
app.MapRazorPages();
app.Run();
