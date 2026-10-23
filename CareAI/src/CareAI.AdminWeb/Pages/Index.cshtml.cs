using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace CareAI.AdminWeb.Pages;
public sealed class IndexModel : PageModel
{
    public IActionResult OnGet() => RedirectToPage("/Accounts/Index");
}
