using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CareAI.AdminWeb.Services;

public sealed class AdminPageFilter : IAsyncPageFilter
{
    public Task OnPageHandlerSelectionAsync(PageHandlerSelectedContext context) => Task.CompletedTask;
    public async Task OnPageHandlerExecutionAsync(PageHandlerExecutingContext context, PageHandlerExecutionDelegate next)
    {
        var result = await next();
        if (result.Exception is not AdminApiException error) return;
        if (error.StatusCode == 403) result.Result = new RedirectToPageResult("/Denied");
        else if (error.StatusCode == 401)
        {
            await context.HttpContext.SignOutAsync("AdminCookie");
            result.Result = new RedirectToPageResult("/Login");
        }
        else if (error.StatusCode == 404) result.Result = new NotFoundResult();
        else result.Result = new RedirectToPageResult("/Error", new { trace = error.TraceId });
        result.ExceptionHandled = true;
    }
}
