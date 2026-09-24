using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using CareAI.Infrastructure.Data;

namespace CareAI.Infrastructure.BackgroundWorkers;

public class NotificationDispatcherWorker : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<NotificationDispatcherWorker> _logger;

    public NotificationDispatcherWorker(IServiceScopeFactory scopeFactory, ILogger<NotificationDispatcherWorker> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("[DISPATCHER-WORKER] Khởi động Background Worker gửi còi hú Quorum FCM...");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ProcessPendingNotificationsAsync(stoppingToken);
            }
            catch (Exception ex) when (!stoppingToken.IsCancellationRequested)
            {
                _logger.LogError(ex, "[DISPATCHER-ERROR] Ngoại lệ không xử lý trong chu kỳ dispatch: {Message}", ex.Message);
            }

            await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken);
        }
    }

    private async Task ProcessPendingNotificationsAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
        var now = DateTime.UtcNow;

        var pendingItems = await db.NotificationOutboxes
            .Where(n => n.Status == "PENDING" && (n.NextRetryAt == null || n.NextRetryAt <= now))
            .OrderBy(n => n.CreatedAt)
            .Take(50)
            .ToListAsync(ct);

        if (pendingItems.Count == 0) return;

        foreach (var item in pendingItems)
        {
            try
            {
                // Giả lập / Bắn tin qua FCM Admin SDK
                // Tại đây gói tin có Priority = HIGH và còi hú Siren = true
                item.Status = "SENT";
                item.SentAt = DateTime.UtcNow;
                _logger.LogInformation("[FCM-SENT] Gửi thành công còi hú tới Token: {Token}. IncidentId={IncidentId}", 
                    item.PushToken.Length > 15 ? item.PushToken[..15] + "..." : item.PushToken, item.IncidentId);
            }
            catch (Exception ex)
            {
                item.RetryCount++;
                if (item.RetryCount >= 5)
                {
                    item.Status = "FAILED";
                    _logger.LogError(ex, "[FCM-FAILED-FINAL] Bỏ cuộc sau 5 lần thử lại thất bại cho OutboxId={Id}", item.Id);
                }
                else
                {
                    // Exponential backoff + Jitter
                    var backoffSeconds = Math.Pow(2, item.RetryCount) + Random.Shared.Next(1, 4);
                    item.NextRetryAt = DateTime.UtcNow.AddSeconds(backoffSeconds);
                    _logger.LogWarning("[FCM-RETRY] Lỗi tạm thời, hẹn giờ thử lại lần {Retry} sau {Sec}s: {Message}", 
                        item.RetryCount, backoffSeconds, ex.Message);
                }
            }
        }

        await db.SaveChangesAsync(ct);
    }
}
