using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using CareAI.Core.DTOs.Admin;
using Microsoft.AspNetCore.Authentication;

namespace CareAI.AdminWeb.Services;

public sealed class AdminApiException(int statusCode, string traceId) : Exception("Không thể hoàn tất yêu cầu đến API quản trị.")
{
    public string? UserMessage { get; init; }
    public int StatusCode { get; } = statusCode;
    public string TraceId { get; } = traceId;
}

public sealed class AdminApiClient(HttpClient http, IHttpContextAccessor accessor)
{
    public Task<AdminLoginResponse> LoginAsync(AdminLoginRequest login, CancellationToken ct) => SendAsync<AdminLoginResponse>(HttpMethod.Post, "auth/login", login, null, ct);
    public Task<AdminIdentity> MeAsync(string token, CancellationToken ct) => SendAsync<AdminIdentity>(HttpMethod.Get, "auth/me", null, token, ct);
    public async Task LogoutAsync(CancellationToken ct) => await SendAsync<object>(HttpMethod.Post, "auth/logout", null, await TokenAsync(), ct);
    public async Task<T> GetAsync<T>(string route, CancellationToken ct) => await SendAsync<T>(HttpMethod.Get, route, null, await TokenAsync(), ct);
    public async Task<T> PostAsync<T>(string route, object body, CancellationToken ct) => await SendAsync<T>(HttpMethod.Post, route, body, await TokenAsync(), ct);
    private async Task<string?> TokenAsync() => accessor.HttpContext is { } context
        ? await context.GetTokenAsync("AdminCookie", "access_token") ?? await context.GetTokenAsync("access_token")
        : null;

    private async Task<T> SendAsync<T>(HttpMethod method, string route, object? body, string? token, CancellationToken ct)
    {
        var trace = accessor.HttpContext?.TraceIdentifier ?? "unavailable";
        try
        {
            using var request = new HttpRequestMessage(method, route);
            if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (body is not null) request.Content = JsonContent.Create(body);
            using var response = await http.SendAsync(request, ct);
            if (!response.IsSuccessStatusCode)
            {
                string? userMessage = null;
                try
                {
                    using var problem = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(ct), cancellationToken: ct);
                    if (problem.RootElement.TryGetProperty("traceId", out var value) && value.ValueKind == JsonValueKind.String
                        && value.GetString() is { Length: > 0 and <= 128 } apiTrace) trace = apiTrace;
                    if (problem.RootElement.TryGetProperty("code", out var code) && code.GetString() == "ADMIN_BUSINESS"
                        && problem.RootElement.TryGetProperty("title", out var title) && title.GetString() is { Length: <= 500 } message) userMessage = message;
                }
                catch (JsonException) { /* Non-JSON failures keep the local correlation ID. */ }
                throw new AdminApiException((int)response.StatusCode, trace) { UserMessage = userMessage };
            }
            if (response.StatusCode == HttpStatusCode.NoContent) return default!;
            return await response.Content.ReadFromJsonAsync<T>(cancellationToken: ct) ?? throw new AdminApiException(503, trace);
        }
        catch (HttpRequestException) { throw new AdminApiException(503, trace); }
        catch (JsonException) { throw new AdminApiException(503, trace); }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested) { throw new AdminApiException(503, trace); }
    }
}
