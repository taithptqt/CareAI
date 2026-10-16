import 'package:intl/intl.dart';

/// Tiện ích đồng bộ múi giờ Việt Nam (UTC+7 / ICT) chuẩn mực cho toàn hệ thống CareAI.
/// Việt Nam không áp dụng quy ước giờ mùa hè (No Daylight Saving Time), cố định UTC+7 quanh năm.
class VietnamTimeHelper {
  /// Chênh lệch chuẩn của Múi giờ Việt Nam so với UTC (+7 giờ)
  static const Duration vnOffset = Duration(hours: 7);

  /// Chuyển đổi an toàn bất kỳ DateTime nào sang Giờ Việt Nam (UTC+7)
  static DateTime toVietnamTime(DateTime? dt) {
    if (dt == null) return DateTime.now().toUtc().add(vnOffset);
    return dt.toUtc().add(vnOffset);
  }

  /// Thời điểm hiện tại theo Giờ Việt Nam (UTC+7)
  static DateTime get now => DateTime.now().toUtc().add(vnOffset);

  /// Mốc bắt đầu ngày hôm nay (00:00:00) theo Giờ Việt Nam
  static DateTime get startOfToday {
    final n = now;
    return DateTime.utc(n.year, n.month, n.day);
  }

  /// Định dạng giờ:phút (HH:mm) theo Giờ Việt Nam (VD: 16:40)
  static String formatHm(DateTime? dt) {
    if (dt == null) return '--:--';
    return DateFormat('HH:mm').format(toVietnamTime(dt));
  }

  /// Định dạng giờ:phút:giây (HH:mm:ss) theo Giờ Việt Nam (VD: 16:40:25)
  static String formatHms(DateTime? dt) {
    if (dt == null) return '--:--:--';
    return DateFormat('HH:mm:ss').format(toVietnamTime(dt));
  }

  /// Định dạng ngày/tháng (dd/MM) theo Giờ Việt Nam (VD: 16/10)
  static String formatDm(DateTime? dt) {
    if (dt == null) return '--/--';
    return DateFormat('dd/MM').format(toVietnamTime(dt));
  }

  /// Định dạng ngày/tháng/năm giờ:phút:giây (dd/MM/yyyy HH:mm:ss) theo Giờ Việt Nam
  static String formatFull(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('dd/MM/yyyy HH:mm:ss').format(toVietnamTime(dt));
  }

  /// Định dạng ngày/tháng/năm giờ:phút (dd/MM/yyyy HH:mm) theo Giờ Việt Nam
  static String formatDateTimeHm(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('dd/MM/yyyy HH:mm').format(toVietnamTime(dt));
  }

  /// Định dạng cảnh báo khẩn cấp (HH:mm:ss dd/MM) theo Giờ Việt Nam
  static String formatAlertTime(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('HH:mm:ss dd/MM').format(toVietnamTime(dt));
  }

  /// Kiểm tra xem một mốc thời gian có thuộc ngày hôm nay theo Giờ Việt Nam không
  static bool isTodayInVietnam(DateTime? dt) {
    if (dt == null) return false;
    final vn = toVietnamTime(dt);
    final current = now;
    return vn.year == current.year && vn.month == current.month && vn.day == current.day;
  }

  /// Lấy tọa độ giờ thực tế (0.0 đến 24.0) trong ngày theo Giờ Việt Nam phục vụ vẽ trục hoành biểu đồ
  static double getHourOfDay(DateTime dt) {
    final vn = toVietnamTime(dt);
    return (vn.hour + (vn.minute / 60.0) + (vn.second / 3600.0)).clamp(0.0, 24.0);
  }
}
