using System.Net;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using CareAI.API.Controllers;
using CareAI.Core.Entities;
using CareAI.Infrastructure.BackgroundWorkers;
using CareAI.Infrastructure.Data;
using CareAI.Infrastructure.WeeklyReports;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace CareAI.UnitTests;

public class WeeklyReportTests
{
    private static readonly DateTime Start = new(2026, 9, 13, 0, 0, 0, DateTimeKind.Utc);
    private static readonly AnonymousWeeklyStatistics Stats = new(70, 500, 7, 6, 2);
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) => send(request, ct);
    }

    private static GeminiWeeklyReportClient Client(HttpMessageHandler handler, string key = "test-key") => new(
        new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(5) },
        Options.Create(new WeeklyReportOptions { GeminiApiKey = key }),
        new RuleBasedWeeklyReportFallbackEngine(), NullLogger<GeminiWeeklyReportClient>.Instance);

    private static HttpResponseMessage Response(string json, HttpStatusCode status = HttpStatusCode.OK) =>
        new(status) { Content = new StringContent(json, Encoding.UTF8, "application/json") };

    private static string ValidResponse(string text) => JsonSerializer.Serialize(new
    {
        candidates = new[] { new { finishReason = "STOP", content = new { parts = new[] { new { text } } } } }
    });

    [Fact]
    public void AnonymizerUsesOnlyNumericAllowlistAndExcludesIdentity()
    {
        var samples = new[]
        {
            new HealthMeasurement { ElderProfileId = "PRIVATE-ID", DeviceId = "PRIVATE-WATCH", PacketId = "PRIVATE-PACKET",
                Unit = "PRIVATE-PHONE", MetricType = "HEART_RATE", Value = 70, Timestamp = Start,
                ElderProfile = new ElderProfile { FullName = "PRIVATE-NAME", EmergencyContact = "PRIVATE-ADDRESS" } },
            new HealthMeasurement { DeviceId = "PRIVATE-WATCH", MetricType = "STEPS", Value = 500, Timestamp = Start }
        };
        var result = new PiiAnonymizerService().Anonymize(samples, 2, Start, Start.AddDays(7), TimeZoneInfo.Utc);
        var json = JsonSerializer.Serialize(result);
        Assert.DoesNotContain("PRIVATE", json);
        Assert.Equal(70, result.AverageHeartRate);
        Assert.Equal(500, result.AverageDailySteps);
        using var document = JsonDocument.Parse(json);
        Assert.Equal(5, document.RootElement.EnumerateObject().Count());
        Assert.All(document.RootElement.EnumerateObject(), p => Assert.Equal(JsonValueKind.Number, p.Value.ValueKind));
    }

    [Fact]
    public void AnonymizerFiltersBadValuesAndDoesNotDoubleCountDevices()
    {
        HealthMeasurement M(string type, double value, string device = "a", int day = 0) => new()
        { MetricType = type, Value = value, DeviceId = device, Timestamp = Start.AddDays(day) };
        var result = new PiiAnonymizerService().Anonymize([
            M("HEART_RATE", double.NaN), M("HEART_RATE", 0), M("HEART_RATE", 400),
            M("STEPS", -1), M("STEPS", 100001), M("STEPS", 100), M("STEPS", 200),
            M("STEPS", 900, "b"), M("STEPS", 10, day: 7), M("STEPS", 10, day: -1),
            M("OTHER", 1), M("STEPS", double.PositiveInfinity)
        ], -2, Start, Start.AddDays(7), TimeZoneInfo.Utc);
        Assert.Null(result.AverageHeartRate);
        Assert.Equal(300, result.AverageDailySteps);
        Assert.Equal(1, result.StepDays);
        Assert.Equal(0, result.AlertCount);
    }

    [Fact]
    public void AnonymizerKeepsNoDataAsNullAndGroupsByLocalDay()
    {
        var zone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Ho_Chi_Minh");
        var result = new PiiAnonymizerService().Anonymize([
            new HealthMeasurement { MetricType = "HEART_RATE", Value = 60, Timestamp = Start.AddHours(16) },
            new HealthMeasurement { MetricType = "HEART_RATE", Value = 80, Timestamp = Start.AddHours(18) }
        ], 0, Start, Start.AddDays(7), zone);
        Assert.Null(result.AverageDailySteps);
        Assert.Equal(2, result.HeartRateDays);
    }

    [Fact]
    public void FallbackIsDeterministicVietnameseAndHasThreeSections()
    {
        var engine = new RuleBasedWeeklyReportFallbackEngine();
        var output = engine.Generate(Stats);
        Assert.Equal(output, engine.Generate(Stats));
        Assert.Contains("1. Tổng quan", output);
        Assert.Contains("2. Điểm tích cực", output);
        Assert.Contains("3. Lời khuyên", output);
        Assert.Contains("70 nhịp/phút", output);
        Assert.Contains("2 nhận định", output);
        Assert.Contains("6 ngày", output);
    }

    [Theory]
    [InlineData(null, null)]
    [InlineData(0d, 0d)]
    public void FallbackDoesNotDeclareMissingDataHealthy(double? hr, double? steps)
    {
        var output = new RuleBasedWeeklyReportFallbackEngine().Generate(new(hr, steps, 0, 0, 0));
        Assert.Contains("không xác nhận sức khỏe hoàn toàn bình thường", output);
        Assert.Contains("không phải chẩn đoán", output);
    }

    [Fact]
    public async Task GeminiSendsOnlyAggregatesInUserPayloadAndParsesThreeSections()
    {
        var client = Client(new Handler(async (request, ct) =>
        {
            Assert.Equal("generativelanguage.googleapis.com", request.RequestUri!.Host);
            Assert.DoesNotContain("test-key", request.RequestUri.ToString());
            Assert.Equal("test-key", request.Headers.GetValues("x-goog-api-key").Single());
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
            var payload = body.RootElement.GetProperty("contents")[0].GetProperty("parts")[0].GetProperty("text").GetString();
            Assert.Equal(JsonSerializer.Serialize(Stats), payload);
            return Response(ValidResponse("{\"overview\":\"Tổng quan\",\"observations\":\"Lưu ý\",\"advice\":\"Hỏi thăm\"}"));
        }));
        var result = await client.GenerateAsync(Stats, CancellationToken.None);
        Assert.Equal("GEMINI", result.Source);
        Assert.Contains("Hỏi thăm", result.Content);
    }

    [Theory]
    [InlineData(429)] [InlineData(500)] [InlineData(401)]
    public async Task HttpFailureImmediatelyUsesDeterministicFallback(int status)
    {
        var calls = 0;
        var client = Client(new Handler((_, _) => { calls++; return Task.FromResult(Response("error", (HttpStatusCode)status)); }));
        var result = await client.GenerateAsync(Stats, CancellationToken.None);
        Assert.Equal("RULE_BASED", result.Source);
        Assert.Equal(new RuleBasedWeeklyReportFallbackEngine().Generate(Stats), result.Content);
        Assert.Equal(1, calls); // No retry delay before fallback.
    }

    [Theory]
    [InlineData("not-json")] [InlineData("{}")] [InlineData("{\"candidates\":[]}")]
    [InlineData("{\"candidates\":[{\"finishReason\":\"SAFETY\"}]}")]
    public async Task BrokenOrBlockedResponseFallsBack(string response)
    {
        var result = await Client(new Handler((_, _) => Task.FromResult(Response(response)))).GenerateAsync(Stats, CancellationToken.None);
        Assert.Equal("RULE_BASED", result.Source);
    }

    [Theory]
    [InlineData("{}")] [InlineData("{\"overview\":\"\",\"observations\":\"x\",\"advice\":\"x\"}")]
    public async Task MissingSectionsFallBack(string response)
    {
        var result = await Client(new Handler((_, _) => Task.FromResult(Response(ValidResponse(response))))).GenerateAsync(Stats, CancellationToken.None);
        Assert.Equal("RULE_BASED", result.Source);
    }

    [Fact]
    public async Task NetworkFailureFallsBack() => Assert.Equal("RULE_BASED", (await Client(new Handler((_, _) =>
        throw new HttpRequestException())).GenerateAsync(Stats, CancellationToken.None)).Source);

    [Fact]
    public async Task TimeoutFallsBackWithinFiveSecondsPlusSchedulingTolerance()
    {
        var client = Client(new Handler(async (_, ct) => { await Task.Delay(Timeout.Infinite, ct); return Response("{}"); }));
        var started = System.Diagnostics.Stopwatch.StartNew();
        Assert.Equal("RULE_BASED", (await client.GenerateAsync(Stats, CancellationToken.None)).Source);
        Assert.InRange(started.Elapsed.TotalSeconds, 4, 8);
    }

    [Fact]
    public async Task NoApiKeyNeverCallsNetwork()
    {
        Assert.Equal("RULE_BASED", (await Client(new Handler((_, _) => throw new Xunit.Sdk.XunitException("Unexpected network")), "")
            .GenerateAsync(Stats, CancellationToken.None)).Source);
    }

    [Fact]
    public async Task HostCancellationDoesNotBecomeFallback()
    {
        using var source = new CancellationTokenSource();
        var client = Client(new Handler(async (_, ct) => { source.Cancel(); await Task.Delay(10, ct); return Response("{}"); }));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => client.GenerateAsync(Stats, source.Token));
    }

    [Theory]
    [InlineData(6, 13)] [InlineData(7, 20)] [InlineData(8, 20)]
    public void SundayScheduleUses0700Boundary(int hour, int expectedDay)
    {
        Assert.Equal(expectedDay, WeeklyReportService.LatestDueSunday(new DateTime(2026, 9, 20, hour, 0, 0, DateTimeKind.Utc), TimeZoneInfo.Utc).Day);
    }

    [Fact]
    public async Task PersistsReportAndOutboxOnceAndEnforcesReadAuthorization()
    {
        using var db = new CareAiDbContext(new DbContextOptionsBuilder<CareAiDbContext>().UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.ElderProfiles.Add(new ElderProfile { Id = "elder" });
        db.ElderCaregivers.Add(new ElderCaregiver { ElderProfileId = "elder", CaregiverId = "caregiver", IsActive = true });
        db.CaregiverPushTokens.Add(new CaregiverPushToken { Id = "token", CaregiverId = "caregiver", PushToken = "private-token" });
        await db.SaveChangesAsync();
        var service = new WeeklyReportService(db, new PiiAnonymizerService(), Client(new Handler((_, _) => throw new HttpRequestException())),
            Options.Create(new WeeklyReportOptions { TimeZoneId = "UTC" }), NullLogger<WeeklyReportService>.Instance);
        await service.GenerateForElderAsync("elder", Start.AddDays(7).AddHours(7), CancellationToken.None);
        await service.GenerateForElderAsync("elder", Start.AddDays(7).AddHours(8), CancellationToken.None);
        var report = Assert.Single(await db.WeeklyHealthReports.ToListAsync());
        Assert.Equal("RULE_BASED", report.Source);
        Assert.Single(await db.WeeklyReportNotifications.ToListAsync());
        var controller = new HealthReportsController(db) { ControllerContext = new ControllerContext { HttpContext = new DefaultHttpContext() } };
        Assert.IsType<ForbidResult>(await controller.Report("elder", report.Id, CancellationToken.None));
        controller.HttpContext.User = new ClaimsPrincipal(new ClaimsIdentity([new Claim(ClaimTypes.NameIdentifier, "caregiver")], "test"));
        Assert.IsType<OkObjectResult>(await controller.Report("elder", report.Id, CancellationToken.None));
        Assert.IsType<ForbidResult>(await controller.Report("someone-else", report.Id, CancellationToken.None));
        Assert.IsType<NotFoundResult>(await controller.Report("elder", report.Id + 10, CancellationToken.None));
        Assert.IsType<OkObjectResult>(await controller.Reports("elder", CancellationToken.None));
        Assert.IsType<OkObjectResult>(await controller.Insights("elder", CancellationToken.None));
    }
}
