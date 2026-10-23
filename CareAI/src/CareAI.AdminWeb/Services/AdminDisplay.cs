using System.Globalization;

namespace CareAI.AdminWeb.Services;

public static class AdminDisplay
{
    // Asia/Saigon is UTC+07:00 for the supported contemporary timestamps.
    public static string Time(DateTimeOffset? value) => value?.ToOffset(TimeSpan.FromHours(7))
        .ToString("dd/MM/yyyy HH:mm", CultureInfo.InvariantCulture) ?? "Chưa có dữ liệu";

    public static string Status(string value) => value switch
    {
        "Active" => "Hoạt động", "Suspended" => "Tạm ngưng", "Open" => "Chưa tiếp nhận",
        "Acknowledged" => "Đã tiếp nhận", "Resolved" => "Đã giải quyết",
        "Online" => "Có heartbeat mới", "Offline" => "Mất heartbeat", "Unknown" => "Chưa xác định",
        "NotSupported" => "Chưa hỗ trợ đình chỉ", "Revoked" => "Đã thu hồi",
        "Critical" => "Khẩn cấp", "MANUAL_SOS" => "SOS thủ công", "FALL" => "Phát hiện ngã",
        "InProgress" => "Đang xử lý", "New" => "Mới nhận",
        _ => value
    };
}
