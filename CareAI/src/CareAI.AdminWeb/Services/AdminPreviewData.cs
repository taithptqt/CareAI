using CareAI.Core.DTOs.Admin;

namespace CareAI.AdminWeb.Services;

/// <summary>Fictional, fixed snapshot. Only reachable through the Development preview gate.</summary>
public sealed class AdminPreviewData
{
    public DateTimeOffset AsOfUtc { get; } = new(2026, 10, 23, 3, 0, 0, TimeSpan.Zero);
    public IReadOnlyList<AdminAccountSummary> Accounts { get; }
    public IReadOnlyList<AdminIncidentSummary> Incidents { get; }
    public IReadOnlyList<AdminDeviceSummary> Devices { get; }
    public IReadOnlyList<string> Elders { get; } = ["Hồ sơ mẫu A", "Hồ sơ mẫu B", "Hồ sơ mẫu C"];

    public AdminPreviewData()
    {
        Accounts = Enumerable.Range(1, 28).Select(i => new AdminAccountSummary(
            $"demo-account-{i:00}", $"Người thân mẫu {i:00}", $"n***{i:00}@example.invalid",
            "•••• ••• 000", AsOfUtc.AddDays(-i), i == 7 ? "Suspended" : "Active",
            i % 9 == 0 ? AsOfUtc.AddMinutes(15) : null, i <= 3 ? 1 : 0)).ToArray();
        Incidents = [
            new("demo-incident-01", Elders[0], "MANUAL_SOS", "Critical", "Open", AsOfUtc.AddMinutes(-4)),
            new("demo-incident-02", Elders[1], "FALL", "Critical", "Acknowledged", AsOfUtc.AddMinutes(-19))
        ];
        Devices = [
            new("demo-device-01", "Điện thoại mẫu A", Elders[0], true, AsOfUtc.AddMinutes(-1), "Online", null),
            new("demo-device-02", "Đồng hồ mẫu B", Elders[1], true, AsOfUtc.AddMinutes(-18), "Offline", 24),
            new("demo-device-03", "Điện thoại mẫu C", Elders[2], true, null, "Unknown", null)
        ];
    }

    public AdminOverviewResponse Overview => new(Accounts.Count, Elders.Count,
        Devices.Count(d => d.IsActive), Incidents.Count(i => i.Status is "Open" or "Acknowledged"),
        Devices.Count(d => d.ConnectionStatus == "Offline"), AsOfUtc,
        Incidents.Where(i => i.Status is "Open" or "Acknowledged").ToArray(),
        Devices.Where(d => d.ConnectionStatus == "Offline").ToArray());
}
