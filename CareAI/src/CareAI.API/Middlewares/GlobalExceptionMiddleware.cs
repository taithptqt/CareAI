using System.Net;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;

namespace CareAI.API.Middlewares;

/// <summary>
/// Middleware bắt và bọc toàn bộ ngoại lệ hệ thống không được xử lý (Unhandled Exceptions).
/// Phân loại chi tiết lỗi CSDL Azure SQL (Paused / Quota / Timeout), Concurrency Conflict và lỗi nội bộ
/// để trả về chuẩn JSON rõ ràng cho Client, hỗ trợ gỡ lỗi và trải nghiệm người dùng.
/// </summary>
public class GlobalExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionMiddleware> _logger;

    public GlobalExceptionMiddleware(RequestDelegate next, ILogger<GlobalExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        _logger.LogError(exception, "[GLOBAL-EXCEPTION] Ngoại lệ chưa được xử lý tại {Method} {Path}: {Message}",
            context.Request.Method, context.Request.Path, exception.Message);

        if (context.Response.HasStarted)
        {
            _logger.LogWarning("[GLOBAL-EXCEPTION] Phản hồi đã được gửi một phần về client, không thể ghi đè body.");
            return;
        }

        context.Response.ContentType = "application/json; charset=utf-8";

        string errorMessage;
        string errorCode;
        int statusCode;

        var sqlEx = FindSqlException(exception);
        if (sqlEx != null)
        {
            var msg = sqlEx.Message;
            if (msg.Contains("paused", StringComparison.OrdinalIgnoreCase) ||
                msg.Contains("free amount allowance", StringComparison.OrdinalIgnoreCase))
            {
                statusCode = (int)HttpStatusCode.ServiceUnavailable; // 503
                errorMessage = "Cơ sở dữ liệu đám mây Azure SQL đang bị tạm dừng (Paused) do vượt quá hạn mức miễn phí hàng tháng. Vui lòng mở lại CSDL trên Azure Portal hoặc chuyển sang máy chủ Local.";
                errorCode = "DATABASE_PAUSED";
            }
            else if (msg.Contains("cannot open database", StringComparison.OrdinalIgnoreCase) ||
                     msg.Contains("login failed", StringComparison.OrdinalIgnoreCase))
            {
                statusCode = (int)HttpStatusCode.ServiceUnavailable; // 503
                errorMessage = "Xác thực CSDL SQL Server thất bại hoặc cơ sở dữ liệu không tồn tại.";
                errorCode = "DATABASE_AUTH_FAILED";
            }
            else if (sqlEx.Number == -2 || msg.Contains("timeout", StringComparison.OrdinalIgnoreCase))
            {
                statusCode = (int)HttpStatusCode.GatewayTimeout; // 504
                errorMessage = "Hết thời gian chờ kết nối cơ sở dữ liệu SQL Server (Database Timeout).";
                errorCode = "DATABASE_TIMEOUT";
            }
            else
            {
                statusCode = (int)HttpStatusCode.InternalServerError; // 500
                errorMessage = $"Lỗi cơ sở dữ liệu SQL Server (Mã SQL: {sqlEx.Number}): {sqlEx.Message}";
                errorCode = "DATABASE_ERROR";
            }
        }
        else if (exception is DbUpdateConcurrencyException)
        {
            statusCode = (int)HttpStatusCode.Conflict; // 409
            errorMessage = "Xung đột dữ liệu đồng thời (Optimistic Concurrency Conflict). Bản ghi đã được cập nhật bởi một phiên khác.";
            errorCode = "CONCURRENCY_CONFLICT";
        }
        else if (exception is DbUpdateException dbUpdateEx)
        {
            statusCode = (int)HttpStatusCode.BadRequest; // 400
            errorMessage = $"Lỗi ràng buộc dữ liệu: {dbUpdateEx.InnerException?.Message ?? dbUpdateEx.Message}";
            errorCode = "DATABASE_UPDATE_ERROR";
        }
        else if (exception is TimeoutException)
        {
            statusCode = (int)HttpStatusCode.GatewayTimeout; // 504
            errorMessage = "Xử lý yêu cầu quá thời gian chờ (Request Timeout). Vui lòng thử lại sau.";
            errorCode = "REQUEST_TIMEOUT";
        }
        else if (exception is UnauthorizedAccessException)
        {
            statusCode = (int)HttpStatusCode.Unauthorized; // 401
            errorMessage = "Bạn không có quyền truy cập tài nguyên này.";
            errorCode = "UNAUTHORIZED";
        }
        else
        {
            statusCode = (int)HttpStatusCode.InternalServerError; // 500
            errorMessage = $"Máy chủ CareAI gặp lỗi xử lý nội bộ: {exception.Message}";
            errorCode = "INTERNAL_SERVER_ERROR";
        }

        context.Response.StatusCode = statusCode;

        var responsePayload = new
        {
            error = errorMessage,
            code = errorCode,
            status = statusCode,
            path = context.Request.Path.Value,
            timestamp = DateTime.UtcNow
        };

        var json = JsonSerializer.Serialize(responsePayload, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        });

        await context.Response.WriteAsync(json);
    }

    private static SqlException? FindSqlException(Exception? ex)
    {
        while (ex != null)
        {
            if (ex is SqlException sqlEx)
                return sqlEx;
            ex = ex.InnerException;
        }
        return null;
    }
}
