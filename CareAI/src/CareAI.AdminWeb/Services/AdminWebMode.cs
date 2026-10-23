namespace CareAI.AdminWeb.Services;

public sealed class AdminWebMode(IWebHostEnvironment environment, IConfiguration configuration)
{
    public bool Preview { get; } = environment.IsDevelopment() && configuration.GetValue<bool>("AdminWeb:EnablePreview");
    public bool Live { get; } = (environment.IsDevelopment() || configuration.GetValue<bool>("AdminWeb:ProductionReady")) && configuration.GetValue<bool>("AdminWeb:EnableLive")
        && !configuration.GetValue<bool>("AdminWeb:EnablePreview");
}
