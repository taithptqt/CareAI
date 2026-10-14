namespace CareAI.Core.Entities;

public class DeviceRegistration
{
    public string Id { get; set; } = Guid.NewGuid().ToString(); // DeviceId
    public string ElderProfileId { get; set; } = string.Empty;
    public ElderProfile ElderProfile { get; set; } = null!;

    public string DeviceTokenHash { get; set; } = string.Empty; // SHA-256 lowercase 64 chars
    public string DeviceType { get; set; } = string.Empty;       // Smartwatch | CompanionPhone
    public string? DeviceModel { get; set; }                     // Tên thương mại / model thiết bị thật (ví dụ Galaxy Watch6)
    public string? DisconnectReason { get; set; }                // Lý do ngắt kết nối: BLUETOOTH_OFF | SIGNAL_LOST | null
    public bool? IsWatchWorn { get; set; }                       // Trạng thái đang đeo trên cổ tay: true = đang đeo, false = đã tháo, null = chưa xác định
    public bool? IsWatchCharging { get; set; }                   // Trạng thái cắm sạc: true = đang sạc, false = không sạc, null = chưa xác định
    public int? WatchBatteryLevel { get; set; }                  // Phần trăm pin đồng hồ: 0 - 100, null = chưa xác định
    public string FirmwareVersion { get; set; } = "1.0.0";
    public bool IsActive { get; set; } = true;
    public DateTime LastHeartbeat { get; set; } = DateTime.UtcNow;
    public DateTime RegisteredAt { get; set; } = DateTime.UtcNow;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAt { get; set; } = DateTime.UtcNow;
}
