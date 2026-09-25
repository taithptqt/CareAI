using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using CareAI.API.Middlewares;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.Engines;
using CareAI.Infrastructure.Notifications;

var builder = WebApplication.CreateBuilder(args);

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

// 3. ĐĂNG KÝ CORE ENGINES
builder.Services.AddScoped<TelemetryEngine>();
builder.Services.AddScoped<ClinicalDiagnosticEngine>();
builder.Services.AddScoped<DeviceStaleEngine>();
builder.Services.AddScoped<NotificationDispatchEngine>();
builder.Services.Configure<AlertingOptions>(builder.Configuration.GetSection(AlertingOptions.SectionName));
builder.Services.AddScoped<AlertSlaEngine>();
builder.Services.AddScoped<UrgentTelemetryEngine>();
builder.Services.AddSingleton<IPushSender, FirebasePushSender>();

// 4. ĐĂNG KÝ HỆ THỐNG BACKGROUND WORKERS
builder.Services.AddHostedService<NotificationDispatcherWorker>();
builder.Services.AddHostedService<AlertSlaWorker>();
builder.Services.AddHostedService<WatchdogBackgroundWorker>();
builder.Services.AddHostedService<DataRetentionBackgroundWorker>();

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
    });

builder.Services.AddAuthorization();

builder.Services.AddControllers();
builder.Services.AddHealthChecks();
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

// Middleware xác thực Token tĩnh của thiết bị phần cứng (X-DeviceId, X-Device-Token)
app.UseMiddleware<DeviceTokenAuthMiddleware>();

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

// 7. TỰ ĐỘNG KHỞI TẠO CƠ SỞ DỮ LIỆU & SCHEMA IDEMPOTENT KHI KHỞI ĐỘNG
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
