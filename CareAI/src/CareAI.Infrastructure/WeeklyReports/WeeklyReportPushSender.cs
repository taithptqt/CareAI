using FirebaseAdmin;
using FirebaseAdmin.Messaging;
using Google.Apis.Auth.OAuth2;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.WeeklyReports;

public sealed class ReportPushOptions
{
    public bool Enabled { get; set; }
    public string ProjectId { get; set; } = string.Empty;
}

public interface IWeeklyReportPushSender
{
    Task SendAsync(string token, long reportId, string elderId, CancellationToken ct);
}

public sealed class WeeklyReportPushSender(IOptions<ReportPushOptions> options) : IWeeklyReportPushSender, IDisposable
{
    private FirebaseApp? _app;

    public async Task SendAsync(string token, long reportId, string elderId, CancellationToken ct)
    {
        if (!options.Value.Enabled) throw new InvalidOperationException("Report push is disabled");
        _app ??= FirebaseApp.Create(new AppOptions
        {
            Credential = await GoogleCredential.GetApplicationDefaultAsync(ct),
            ProjectId = options.Value.ProjectId
        }, "careai-weekly-reports");
#pragma warning disable CS0618
        await FirebaseMessaging.GetMessaging(_app).SendAsync(new Message
        {
            Token = token,
            Notification = new Notification
            {
                Title = "Báo cáo tuần đã sẵn sàng",
                Body = "Mở CareAI để xem tổng kết và hỏi thăm người thân."
            },
            Data = new Dictionary<string, string>
            {
                ["type"] = "WEEKLY_REPORT", ["reportId"] = reportId.ToString(), ["elderProfileId"] = elderId
            }
        }, ct);
#pragma warning restore CS0618
    }

    public void Dispose() => _app?.Delete();
}
