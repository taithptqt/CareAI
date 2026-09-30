using CareAI.Core.Entities;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.WeeklyReports;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace CareAI.UnitTests;

public class WeeklyNotificationTests
{
    private sealed class Sender(bool fail) : IWeeklyReportPushSender
    {
        public int Calls { get; private set; }
        public Task SendAsync(string token, long reportId, string elderId, CancellationToken ct)
        {
            Calls++;
            if (fail) throw new HttpRequestException();
            return Task.CompletedTask;
        }
    }

    [Theory]
    [InlineData(true, false, true, "SENT", 1)]
    [InlineData(true, true, true, "PENDING", 1)]
    [InlineData(true, false, false, "CANCELLED", 0)]
    [InlineData(false, false, true, "PENDING", 0)]
    public async Task DispatchHonorsPermissionsAndDoesNotFalselyMarkFailuresSent(
        bool enabled, bool fail, bool allowed, string expected, int calls)
    {
        var services = new ServiceCollection();
        var database = Guid.NewGuid().ToString();
        services.AddDbContext<CareAiDbContext>(o => o.UseInMemoryDatabase(database));
        await using var provider = services.BuildServiceProvider();
        await using (var scope = provider.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<CareAiDbContext>();
            db.CaregiverPushTokens.Add(new CaregiverPushToken { Id = "token", CaregiverId = "caregiver", PushToken = "test-token" });
            db.ElderCaregivers.Add(new ElderCaregiver { CaregiverId = "caregiver", ElderProfileId = "elder", IsActive = allowed });
            db.WeeklyReportNotifications.Add(new WeeklyReportNotification
            {
                CaregiverPushTokenId = "token", NextAttemptUtc = DateTime.UtcNow.AddMinutes(-1),
                WeeklyHealthReport = new WeeklyHealthReport { ElderProfileId = "elder", Content = "test" }
            });
            await db.SaveChangesAsync();
        }
        var sender = new Sender(fail);
        var worker = new WeeklyReportNotificationWorker(provider.GetRequiredService<IServiceScopeFactory>(), sender,
            Options.Create(new ReportPushOptions { Enabled = enabled }), NullLogger<WeeklyReportNotificationWorker>.Instance);
        await worker.DispatchAsync(CancellationToken.None);
        await worker.DispatchAsync(CancellationToken.None);
        await using var check = provider.CreateAsyncScope();
        var item = await check.ServiceProvider.GetRequiredService<CareAiDbContext>().WeeklyReportNotifications.SingleAsync();
        Assert.Equal(expected, item.Status);
        Assert.Equal(calls, sender.Calls);
        Assert.Equal(fail && enabled ? 1 : 0, item.RetryCount);
    }
}
