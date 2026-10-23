using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Admin;

public sealed class AdminErrorMiddleware(RequestDelegate next, ILogger<AdminErrorMiddleware> logger, AdminSecurityOptions settings)
{
    public async Task InvokeAsync(HttpContext context)
    {
        if (!context.Request.Path.StartsWithSegments("/api/v1/admin")) { await next(context); return; }
        context.Response.Headers.CacheControl = "no-store";
        try
        {
            // AdminWeb-only server boundary, in addition to individual admin authentication.
            if (!settings.Enabled) { await WriteProblem(context, 404); return; }
            var clientKey = context.Request.Headers["X-CareAI-AdminWeb-Key"].ToString();
            if (!context.Request.IsHttps || clientKey.Length > 512 || !System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
                System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(clientKey)),
                System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(settings.WebClientKey))))
            { await WriteProblem(context, 401); return; }
            await next(context);
            if (context.Response.StatusCode is 401 or 403 or 404 or 429 && !context.Response.HasStarted)
                await WriteProblem(context, context.Response.StatusCode);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
        catch (CareAI.Infrastructure.Admin.AdminBusinessException error)
        {
            context.Response.StatusCode = error.Status;
            var problem = new ProblemDetails { Status = error.Status, Title = error.Message };
            problem.Extensions["traceId"] = context.TraceIdentifier;
            problem.Extensions["code"] = "ADMIN_BUSINESS";
            await context.Response.WriteAsJsonAsync(problem);
        }
        catch (Exception error)
        {
            if (context.Response.HasStarted) throw;
            logger.LogWarning("Admin request failed: {ErrorType}; trace {TraceId}", error.GetType().Name, context.TraceIdentifier);
            if (context.RequestServices.GetRequiredService<IWebHostEnvironment>().IsDevelopment())
                logger.LogDebug("Admin failure location: {StackTrace}", error.StackTrace);
            context.Response.Clear();
            await WriteProblem(context, error is DbUpdateConcurrencyException ? 409 : 503);
        }
    }
    private static Task WriteProblem(HttpContext context, int status)
    {
        context.Response.StatusCode = status;
        context.Response.Headers.CacheControl = "no-store";
        var problem = new ProblemDetails { Status = status, Title = status switch
        {
            401 => "Chưa xác thực hoặc phiên đã hết hạn.", 403 => "Không có quyền truy cập.",
            404 => "Không tìm thấy tài nguyên.", 409 => "Dữ liệu đã thay đổi. Vui lòng tải lại.",
            429 => "Vượt giới hạn yêu cầu.", _ => "Dịch vụ quản trị tạm thời không khả dụng."
        }};
        problem.Extensions["traceId"] = context.TraceIdentifier;
        problem.Extensions["code"] = "ADMIN_" + status;
        return context.Response.WriteAsJsonAsync(problem, options: (System.Text.Json.JsonSerializerOptions?)null,
            contentType: "application/problem+json", cancellationToken: context.RequestAborted);
    }
}
