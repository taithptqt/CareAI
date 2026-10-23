namespace CareAI.Core.DTOs.Admin;

// Explicit read models: never expose EF entities, credentials or clinical data.
public sealed record AdminListResponse<T>(
    IReadOnlyList<T> Items, int TotalCount, int Page, int PageSize, DateTimeOffset AsOfUtc);

public sealed record AdminAccountSummary(
    string Id, string FullName, string MaskedEmail, string MaskedPhone,
    DateTimeOffset CreatedAt, string AdministrativeStatus,
    DateTimeOffset? LockoutEndUtc, int ActiveCareLinks);

public sealed record AdminIncidentSummary(
    string Id, string ElderDisplayName, string Type, string Severity,
    string Status, DateTimeOffset CreatedAt);

public sealed record AdminDeviceSummary(
    string Id, string Model, string ElderDisplayName, bool IsActive,
    DateTimeOffset? LastHeartbeatUtc, string ConnectionStatus, int? BatteryPercent);

public sealed record AdminOverviewResponse(
    int AccountCount, int ElderCount, int ActiveDeviceCount, int ActiveIncidentCount,
    int OfflineDeviceCount, DateTimeOffset AsOfUtc,
    IReadOnlyList<AdminIncidentSummary> ActiveIncidents,
    IReadOnlyList<AdminDeviceSummary> OfflineDevices);
