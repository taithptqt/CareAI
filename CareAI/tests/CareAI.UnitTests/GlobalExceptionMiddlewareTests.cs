using System.IO;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using CareAI.API.Middlewares;
using Xunit;

namespace CareAI.UnitTests;

public class GlobalExceptionMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_WhenDbUpdateConcurrencyException_ReturnsConflict409()
    {
        // Arrange
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Request.Path = "/api/v1/incidents/test/acknowledge";

        var middleware = new GlobalExceptionMiddleware(
            next: (ctx) => throw new DbUpdateConcurrencyException("Optimistic concurrency error"),
            logger: NullLogger<GlobalExceptionMiddleware>.Instance);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.Equal(409, context.Response.StatusCode);
        context.Response.Body.Seek(0, SeekOrigin.Begin);
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        using var doc = JsonDocument.Parse(json);
        Assert.Equal("CONCURRENCY_CONFLICT", doc.RootElement.GetProperty("code").GetString());
        Assert.Contains("Xung đột dữ liệu", doc.RootElement.GetProperty("error").GetString());
    }

    [Fact]
    public async Task InvokeAsync_WhenTimeoutException_ReturnsGatewayTimeout504()
    {
        // Arrange
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Request.Path = "/api/v1/dashboard/elder/1";

        var middleware = new GlobalExceptionMiddleware(
            next: (ctx) => throw new TimeoutException("Operation timed out"),
            logger: NullLogger<GlobalExceptionMiddleware>.Instance);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.Equal(504, context.Response.StatusCode);
        context.Response.Body.Seek(0, SeekOrigin.Begin);
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        using var doc = JsonDocument.Parse(json);
        Assert.Equal("REQUEST_TIMEOUT", doc.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task InvokeAsync_WhenUnauthorizedAccessException_ReturnsUnauthorized401()
    {
        // Arrange
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Request.Path = "/api/v1/caregivers/elders";

        var middleware = new GlobalExceptionMiddleware(
            next: (ctx) => throw new UnauthorizedAccessException("Access denied"),
            logger: NullLogger<GlobalExceptionMiddleware>.Instance);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.Equal(401, context.Response.StatusCode);
        context.Response.Body.Seek(0, SeekOrigin.Begin);
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        using var doc = JsonDocument.Parse(json);
        Assert.Equal("UNAUTHORIZED", doc.RootElement.GetProperty("code").GetString());
    }

    [Fact]
    public async Task InvokeAsync_WhenGenericException_ReturnsInternalServerError500()
    {
        // Arrange
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Request.Path = "/api/v1/auth/login";

        var middleware = new GlobalExceptionMiddleware(
            next: (ctx) => throw new InvalidOperationException("Something unexpected occurred"),
            logger: NullLogger<GlobalExceptionMiddleware>.Instance);

        // Act
        await middleware.InvokeAsync(context);

        // Assert
        Assert.Equal(500, context.Response.StatusCode);
        context.Response.Body.Seek(0, SeekOrigin.Begin);
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        using var doc = JsonDocument.Parse(json);
        Assert.Equal("INTERNAL_SERVER_ERROR", doc.RootElement.GetProperty("code").GetString());
        Assert.Contains("Máy chủ CareAI gặp lỗi xử lý nội bộ", doc.RootElement.GetProperty("error").GetString());
    }
}
