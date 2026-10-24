using System.Text;
using CareAI.AdminWeb.Services;
using CareAI.API.Admin;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using CareAI.API.Middlewares;
using CareAI.Core.Interfaces;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Channels;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using CareAI.Infrastructure.Services;
using CareAI.Infrastructure.Notifications;
using CareAI.Infrastructure.AnomalyDetection;
using CareAI.Infrastructure.WeeklyReports;

var builder = WebApplication.CreateBuilder(args);
var adminOnlyHost = builder.Environment.IsDevelopment()
    && builder.Configuration.GetValue<bool>("AdminSecurity:AdminOnlyHost");

// Explicit origins apply in Production too, where the Azure API serves Flutter web.
var webOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
    ?? Array.Empty<string>();
builder.Services.AddCors(options => options.AddPolicy("CareAiWeb", policy =>
    policy.WithOrigins(webOrigins)
        .AllowAnyHeader()
        .AllowAnyMethod()));

// 1. CẤU HÌNH CƠ SỞ DỮ LIỆU SQL SERVER
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ??
    "Server=.\\SQLEXPRESS;Database=CareAiDb;Integrated Security=True;TrustServerCertificate=True;";

builder.Services.AddDbContext<CareAiDbContext>(options =>
    options.UseSqlServer(connectionString, sql =>
    {
        sql.EnableRetryOnFailure(maxRetryCount: 3, maxRetryDelay: TimeSpan.FromSeconds(5), errorNumbersToAdd: null);
    }));

// 2. CẤU HÌNH BỘ ĐỆM RAM CHỐNG OOM (LÁ CHẮN BẢO VỆ TÀI NGUYÊN)
builder.Services.AddMemoryCache(options =>
{
    options.SizeLimit = 50_000;
    options.CompactionPercentage = 0.20;
});

// 2.1 HÀNG ĐỢI PHI KHÓA NON-BLOCKING MEMORY CHANNEL (NHIỆM VỤ 1.2)
builder.Services.AddSingleton<ITelemetryBatchQueue, TelemetryBatchQueue>();

// 3. ĐĂNG KÝ CORE ENGINES & SERVICES
builder.Services.AddScoped<TelemetryEngine>();
builder.Services.AddScoped<IAdaptiveThresholdService, AdaptiveThresholdService>();
builder.Services.AddScoped<ClinicalDiagnosticEngine>();
builder.Services.AddScoped<DeviceStaleEngine>();
builder.Services.AddScoped<NotificationDispatchEngine>();
builder.Services.Configure<AlertingOptions>(builder.Configuration.GetSection(AlertingOptions.SectionName));
builder.Services.AddScoped<AlertSlaEngine>();
builder.Services.AddScoped<UrgentTelemetryEngine>();
builder.Services.AddSingleton<IPushSender, FirebasePushSender>();

// 4. ĐĂNG KÝ HỆ THỐNG BACKGROUND WORKERS
if (!adminOnlyHost)
{
    builder.Services.AddHostedService<TelemetryBatchProcessorWorker>();
    builder.Services.AddHostedService<NotificationDispatcherWorker>();
    builder.Services.AddHostedService<AlertSlaWorker>();
    builder.Services.AddHostedService<WatchdogBackgroundWorker>();
    builder.Services.AddHostedService<DataRetentionBackgroundWorker>();
}

// 4.1 ĐĂNG KÝ HỆ THỐNG ANOMALY DETECTION & GEMINI WEEKLY REPORTS (PHẦN 4)
builder.Services.AddOptions<AnomalyDetectionOptions>()
    .Bind(builder.Configuration.GetSection("AnomalyDetection"))
    .Validate(o => o.Confidence > 0 && o.Confidence < 100, "Confidence must be between 0 and 100")
    .Validate(o => o.MinimumBaselineDays >= 2 && o.MinimumBaselineDays <= 13, "Baseline days must be 2–13")
    .Validate(o => double.IsFinite(o.MinimumUsualMorningSteps) && o.MinimumUsualMorningSteps > 0,
        "MinimumUsualMorningSteps must be positive")
    .Validate(o => TimeZoneInfo.TryFindSystemTimeZoneById(o.TimeZoneId, out _), "Invalid anomaly time zone")
    .ValidateOnStart();
builder.Services.AddSingleton<TimeSeriesAnomalyDetector>();
if (!adminOnlyHost) builder.Services.AddHostedService<AnomalyDetectionWorker>();

builder.Services.AddOptions<WeeklyReportOptions>()
    .Bind(builder.Configuration.GetSection("WeeklyReports"))
    .Validate(o => TimeZoneInfo.TryFindSystemTimeZoneById(o.TimeZoneId, out _), "Invalid weekly report time zone")
    .Validate(o => !string.IsNullOrWhiteSpace(o.GeminiModel), "GeminiModel is required")
    .ValidateOnStart();
builder.Services.AddOptions<ReportPushOptions>().Bind(builder.Configuration.GetSection("ReportPush"))
    .Validate(o => !o.Enabled || !string.IsNullOrWhiteSpace(o.ProjectId), "ReportPush ProjectId required when enabled")
    .ValidateOnStart();
builder.Services.AddSingleton<PiiAnonymizerService>();
builder.Services.AddSingleton<RuleBasedWeeklyReportFallbackEngine>();
builder.Services.AddHttpClient<GeminiWeeklyReportClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(5);
    client.MaxResponseContentBufferSize = 128 * 1024;
});
builder.Services.AddScoped<WeeklyReportService>();
builder.Services.AddSingleton<IWeeklyReportPushSender, WeeklyReportPushSender>();
if (!adminOnlyHost) builder.Services.AddHostedService<WeeklyReportWorker>();
if (!adminOnlyHost) builder.Services.AddHostedService<WeeklyReportNotificationWorker>();

// 5. CẤU HÌNH XÁC THỰC JWT CHO NGƯỜI THÂN
var jwtSecret = builder.Configuration["Jwt:SecretKey"] ?? "CareAiSuperSecretKeyForDevelopment20261234567890!";
var jwtIssuer = builder.Configuration["Jwt:Issuer"] ?? "CareAI.Server";
var jwtAudience = builder.Configuration["Jwt:Audience"] ?? "CareAI.CaregiverApp";

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtAudience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromMinutes(1)
        };
        if (builder.Configuration.GetValue<bool>("AdminSecurity:EnforceCaregiverSessions"))
        {
            options.Events = new JwtBearerEvents
            {
                OnTokenValidated = async context =>
                {
                    var db = context.HttpContext.RequestServices.GetRequiredService<CareAiDbContext>();
                    var cache = context.HttpContext.RequestServices.GetService<Microsoft.Extensions.Caching.Memory.IMemoryCache>();
                    if (!await CareAI.Infrastructure.Admin.CaregiverSessionValidator.IsValidAsync(db, context.Principal!, context.HttpContext.RequestAborted, cache))
                        context.Fail("Caregiver session revoked or suspended.");
                }
            };
        }
    });

builder.Services.AddAuthorization();
builder.Services.AddCareAiAdmin(builder.Configuration, builder.Environment);
builder.Services.AddScoped<CareAI.Infrastructure.Feedback.FeedbackService>();
builder.Services.AddSingleton<CareAI.Core.Interfaces.IEmailSender, CareAI.Infrastructure.Services.SmtpEmailSender>();
builder.Services.AddCareAiAdminWeb(builder.Configuration, builder.Environment);

builder.Services.AddControllers();
builder.Services.AddHealthChecks().AddCheck<DatabaseHealthCheck>("sqlserver");
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "CareAI Sovereignty API", Version = "v111.0" });

    // Cấu hình JWT Bearer trong Swagger UI
    c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "Nhập JWT Token: Bearer {token}",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer"
    });

    c.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();
if (app.Services.GetRequiredService<AdminSecurityOptions>().DisabledReason is { } adminDisabledReason)
    app.Logger.LogWarning("{AdminDisabledReason}", adminDisabledReason);

// Offline, explicit bootstrap. No web host/workers or automatic schema initialization run here.
if (args.Contains("--bootstrap-admin"))
{
    if (!app.Environment.IsDevelopment()) throw new InvalidOperationException("Admin bootstrap is currently Development-only.");
    Console.Write("Admin email: ");
    var email = Console.ReadLine() ?? "";
    Console.Write("Admin display name: ");
    var name = Console.ReadLine() ?? "";
    Console.Write("Password (16+ characters, hidden): ");
    var password = new StringBuilder();
    ConsoleKeyInfo key;
    while ((key = Console.ReadKey(intercept: true)).Key != ConsoleKey.Enter)
    {
        if (key.Key == ConsoleKey.Backspace && password.Length > 0) password.Length--;
        else if (!char.IsControl(key.KeyChar) && password.Length < 256) password.Append(key.KeyChar);
    }
    Console.WriteLine();
    using var bootstrapScope = app.Services.CreateScope();
    await bootstrapScope.ServiceProvider.GetRequiredService<CareAI.Infrastructure.Admin.AdminAuthService>()
        .BootstrapAsync(email, name, password.ToString(), CancellationToken.None);
    password.Clear();
    Console.WriteLine("Initial admin created. No credentials were logged.");
    return;
}

app.UseMiddleware<GlobalExceptionMiddleware>();
app.UseMiddleware<AdminErrorMiddleware>();
if (adminOnlyHost)
{
    app.Use(async (context, next) =>
    {
        if (context.Connection.LocalIpAddress is null || !System.Net.IPAddress.IsLoopback(context.Connection.LocalIpAddress)
            || (!context.Request.Path.StartsWithSegments("/api/v1/admin")
                && !context.Request.Path.StartsWithSegments("/api/v1/caregivers/feedback")))
        { context.Response.StatusCode = 404; return; }
        await next();
    });
}
app.UseRouting();
app.UseRateLimiter();
app.UseCors("CareAiWeb");
app.UseStaticFiles();

// 6. PIPELINE XỬ LÝ HTTP & SWAGGER
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "CareAI API v111.0");
    });
}

// Health check endpoints
app.MapHealthChecks("/health");
app.MapHealthChecks("/healthz");
app.MapGet("/health/capabilities", () => Results.Ok(new
{
    caregiverSessionRevocation = builder.Configuration.GetValue<bool>("AdminSecurity:EnforceCaregiverSessions"),
    deviceRevocationDatabaseCheck = true,
    customerFeedback = true
}));

// Middleware xác thực Token tĩnh của thiết bị phần cứng (X-DeviceId, X-Device-Token)
app.UseMiddleware<DeviceTokenAuthMiddleware>();

app.UseAuthentication();
app.UseAuthorization();
app.UseCareAiAdminWeb(builder.Configuration, builder.Environment);

app.MapControllers();
app.MapRazorPages();

// 7. TỰ ĐỘNG KHỞI TẠO CƠ SỞ DỮ LIỆU & SCHEMA IDEMPOTENT KHI KHỞI ĐỘNG
if (!adminOnlyHost)
using (var scope = app.Services.CreateScope())
{
    var logger = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    try
    {
        await DatabaseMigrationHelper.InitializeDatabaseAsync(connectionString, logger);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "[STARTUP-WARNING] Khởi tạo CSDL gặp lỗi. Tiếp tục chạy.");
    }
}

app.Run();
