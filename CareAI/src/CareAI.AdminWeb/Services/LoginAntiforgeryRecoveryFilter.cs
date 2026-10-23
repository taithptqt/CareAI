using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Core.Infrastructure;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CareAI.AdminWeb.Services;

// Reject stale login submissions, then render a fresh form instead of an empty HTTP 400.
public sealed class LoginAntiforgeryRecoveryFilter : IAlwaysRunResultFilter
{
    public void OnResultExecuting(ResultExecutingContext context)
    {
        if (context.HttpContext.Request.Path == "/Login"
            && context.Result is IAntiforgeryValidationFailedResult)
            context.Result = new RedirectToPageResult("/Login", new { expired = true });
    }

    public void OnResultExecuted(ResultExecutedContext context) { }
}
