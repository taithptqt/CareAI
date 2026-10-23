using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
[IgnoreAntiforgeryToken]
public sealed class ErrorModel : PageModel
{
    public string TraceId { get; private set; } = "";
    public void OnGet(string? trace = null) => TraceId = trace is { Length: <= 128 } ? trace : Activity.Current?.Id ?? HttpContext.TraceIdentifier;
    public void OnPost() => OnGet();
}
