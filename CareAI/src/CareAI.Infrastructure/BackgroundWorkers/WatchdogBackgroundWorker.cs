using CareAI.Infrastructure.Engines;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace CareAI.Infrastructure.BackgroundWorkers;

public class WatchdogBackgroundWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<WatchdogBackgroundWorker> _logger;

    public WatchdogBackgroundWorker(IServiceScopeFactory scopeFactory, ILogger<WatchdogBackgroundWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(60));
        do
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                await scope.ServiceProvider.GetRequiredService<DeviceStaleEngine>()
                    .ScanAsync(DateTime.UtcNow, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                _logger.LogError(ex, "[WATCHDOG-ERROR] Device connectivity scan failed.");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
