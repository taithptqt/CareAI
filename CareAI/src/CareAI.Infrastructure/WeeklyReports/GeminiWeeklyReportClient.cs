using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace CareAI.Infrastructure.WeeklyReports;

public sealed class WeeklyReportOptions
{
    public string TimeZoneId { get; set; } = "Asia/Ho_Chi_Minh";
    public string GeminiApiKey { get; set; } = string.Empty;
    public string GeminiModel { get; set; } = "gemini-2.5-flash";
}

public sealed record GeneratedWeeklyReport(string Content, string Source);

public sealed class GeminiWeeklyReportClient(HttpClient http, IOptions<WeeklyReportOptions> options,
    RuleBasedWeeklyReportFallbackEngine fallback, ILogger<GeminiWeeklyReportClient> logger)
{
    public const string Prompt = """
        Viết báo cáo tuần bằng tiếng Việt, ân cần, dễ hiểu cho gia đình người cao tuổi.
        Chỉ dùng các số liệu tổng hợp được cung cấp. AverageDailySteps chỉ tính ngày có dữ liệu,
        không phải trung bình đủ 7 ngày. Không suy diễn dữ liệu thiếu thành 0 hoặc sức khỏe bình thường.
        Không đặt tên, thêm danh tính, chẩn đoán bệnh, kê thuốc, thay đổi thuốc hoặc bịa số liệu.
        Báo cáo phải có đúng ba phần: 1. Tổng quan sức khỏe tuần;
        2. Điểm tích cực & Cần lưu ý; 3. Lời khuyên sinh hoạt tuần tới.
        Lời khuyên chỉ gồm hỏi thăm giấc ngủ, sinh hoạt, và trao đổi với nhân viên y tế khi có lo ngại.
        Kết thúc bằng: Báo cáo hỗ trợ theo dõi, không phải chẩn đoán y khoa.
        Trả về JSON gồm ba chuỗi không rỗng: overview, observations, advice.
        """;

    public async Task<GeneratedWeeklyReport> GenerateAsync(AnonymousWeeklyStatistics data, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        // Precompute locally; the failover itself performs no I/O or additional delay.
        var backup = new GeneratedWeeklyReport(fallback.Generate(data), "RULE_BASED");
        var settings = options.Value;
        if (string.IsNullOrWhiteSpace(settings.GeminiApiKey)) return backup;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(5));
            using var request = new HttpRequestMessage(HttpMethod.Post,
                $"https://generativelanguage.googleapis.com/v1beta/models/{Uri.EscapeDataString(settings.GeminiModel)}:generateContent");
            request.Headers.Add("x-goog-api-key", settings.GeminiApiKey);
            request.Content = JsonContent.Create(new
            {
                systemInstruction = new { parts = new[] { new { text = Prompt } } },
                contents = new[] { new { role = "user", parts = new[] { new { text = JsonSerializer.Serialize(data) } } } },
                generationConfig = new { temperature = 0.2, maxOutputTokens = 1500, responseMimeType = "application/json" }
            });
            using var response = await http.SendAsync(request, timeout.Token);
            response.EnsureSuccessStatusCode();
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(timeout.Token));
            var candidate = json.RootElement.GetProperty("candidates")[0];
            if (candidate.GetProperty("finishReason").GetString() != "STOP") return backup;
            var text = string.Concat(candidate.GetProperty("content").GetProperty("parts")
                .EnumerateArray().Where(p => p.TryGetProperty("text", out _)).Select(p => p.GetProperty("text").GetString()));
            using var body = JsonDocument.Parse(text);
            string Field(string name)
            {
                var value = body.RootElement.GetProperty(name).GetString();
                if (string.IsNullOrWhiteSpace(value) || value.Length > 4000) throw new FormatException();
                return value.Trim();
            }
            var content = $"1. Tổng quan sức khỏe tuần\n{Field("overview")}\n\n"
                + $"2. Điểm tích cực & Cần lưu ý\n{Field("observations")}\n\n"
                + $"3. Lời khuyên sinh hoạt tuần tới\n{Field("advice")}\n\n"
                + "Báo cáo hỗ trợ theo dõi, không phải chẩn đoán y khoa.";
            return new GeneratedWeeklyReport(content, "GEMINI");
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
        catch (Exception ex) when (ex is HttpRequestException or OperationCanceledException
            or JsonException or KeyNotFoundException or InvalidOperationException or IndexOutOfRangeException or FormatException)
        {
            // Never log request, credentials, response text, or health payloads.
            logger.LogWarning("Weekly AI unavailable ({Failure}); using local report", ex.GetType().Name);
            return backup;
        }
    }
}
