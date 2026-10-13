using Microsoft.Extensions.Diagnostics.HealthChecks;
using CareAI.Infrastructure.Data;

namespace CareAI.API.Middlewares;

/// <summary>
/// Health Check kiểm tra kết nối thực tế tới Cơ sở dữ liệu SQL Server.
/// Trả về Unhealthy (HTTP 503) nếu CSDL bị tạm dừng (Paused), ngắt mạng hoặc sai thông tin xác thực.
/// </summary>
public class DatabaseHealthCheck : IHealthCheck
{
    private readonly IServiceProvider _serviceProvider;

    public DatabaseHealthCheck(IServiceProvider serviceProvider)
    {
        _serviceProvider = serviceProvider;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var scope = _serviceProvider.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            var canConnect = await db.Database.CanConnectAsync(cancellationToken);
            return canConnect
                ? HealthCheckResult.Healthy("Database is connected and ready.")
                : HealthCheckResult.Unhealthy("Cannot connect to SQL Server database.");
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy($"Database connection failed: {ex.Message}");
        }
    }
}
