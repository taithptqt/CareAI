import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kết quả định vị GPS chuẩn y tế CareAI
class GpsLocationResult {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final String provider;
  final bool isRealGps;
  final DateTime timestamp;

  const GpsLocationResult({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.provider,
    required this.isRealGps,
    required this.timestamp,
  });

  /// Chuỗi tọa độ hiển thị chuẩn: '10.776889, 106.700806'
  String get coordinatesFormatted =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  /// Link Google Maps trực tiếp để mở hoặc chia sẻ
  String get googleMapsWebUrl =>
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';

  /// Link chỉ đường trực tiếp tới vị trí nạn nhân trên Google Maps
  String get googleMapsDirectionsUrl =>
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude';

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'provider': provider,
        'isRealGps': isRealGps,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Dịch vụ định vị GPS thực tế và liên kết Google Maps của CareAI
/// TUÂN THỦ NGHIÊM NGẶT: Tuyệt đối KHÔNG sử dụng bản đồ Trung Quốc (Baidu, AutoNavi/Amap, Tencent).
/// Sử dụng liên kết trực tiếp Google Maps chuẩn quốc tế & lấy tọa độ phần cứng thiết bị.
class LocationService {
  LocationService._internal();
  static final LocationService instance = LocationService._internal();

  static const MethodChannel _channel =
      MethodChannel('vn.careai.companion/gps_bridge');

  // Tọa độ dự phòng an toàn (Quận 1, TP. Hồ Chí Minh) khi thiết bị chưa khóa được vệ tinh GPS
  static const double defaultLat = 10.776889;
  static const double defaultLng = 106.700806;

  /// Lấy tọa độ GPS thực tế từ cảm biến phần cứng của điện thoại
  Future<GpsLocationResult> getCurrentLocation({
    bool requestPermissionIfDenied = true,
  }) async {
    try {
      // 1. Kiểm tra và xin quyền vị trí nếu cần
      final hasPermission = await hasLocationPermission();
      if (!hasPermission && requestPermissionIfDenied) {
        await requestLocationPermission();
      }

      // 2. Gọi kênh native Android để lấy vị trí phần cứng tốt nhất
      final dynamic raw = await _channel.invokeMethod('getCurrentLocation');
      if (raw != null && raw is Map) {
        final lat = (raw['latitude'] as num?)?.toDouble();
        final lng = (raw['longitude'] as num?)?.toDouble();
        final acc = (raw['accuracy'] as num?)?.toDouble();
        final prov = (raw['provider'] as String?) ?? 'gps';

        if (lat != null && lng != null && lat != 0.0 && lng != 0.0) {
          final result = GpsLocationResult(
            latitude: lat,
            longitude: lng,
            accuracy: acc,
            provider: prov,
            isRealGps: true,
            timestamp: DateTime.now().toUtc(),
          );

          // Ghi nhớ vị trí gần nhất vào bộ nhớ máy để phục vụ ngoại tuyến
          await _cacheLastLocation(lat, lng);
          return result;
        }
      }
    } catch (e) {
      debugPrint('[LocationService] Lỗi khi lấy GPS thực tế: $e');
    }

    // 3. Fallback: Lấy vị trí đã cache trước đó từ bộ nhớ máy
    final cached = await _getCachedLocation();
    if (cached != null) {
      return cached;
    }

    // 4. Fallback cuối cùng: Vị trí mặc định
    return GpsLocationResult(
      latitude: defaultLat,
      longitude: defaultLng,
      accuracy: null,
      provider: 'default_fallback',
      isRealGps: false,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Mở vị trí tọa độ trực tiếp trong ứng dụng Google Maps hoặc trình duyệt
  Future<bool> openGoogleMaps(double latitude, double longitude, {String? label}) async {
    try {
      final success = await _channel.invokeMethod<bool>('openGoogleMaps', {
        'latitude': latitude,
        'longitude': longitude,
        'label': label ?? 'Vị trí người cao tuổi CareAI',
      });
      return success ?? false;
    } catch (e) {
      debugPrint('[LocationService] Lỗi gọi openGoogleMaps: $e');
      return false;
    }
  }

  /// Mở chỉ đường cứu nạn trực tiếp tới vị trí tọa độ trên Google Maps (Turn-by-turn Navigation)
  Future<bool> openGoogleMapsDirections(double latitude, double longitude) async {
    try {
      final success = await _channel.invokeMethod<bool>('openGoogleMapsDirections', {
        'latitude': latitude,
        'longitude': longitude,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('[LocationService] Lỗi gọi openGoogleMapsDirections: $e');
      return false;
    }
  }

  /// Kiểm tra quyền truy cập vị trí
  Future<bool> hasLocationPermission() async {
    try {
      final hasPerm = await _channel.invokeMethod<bool>('hasLocationPermission');
      return hasPerm ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Yêu cầu cấp quyền vị trí
  Future<void> requestLocationPermission() async {
    try {
      await _channel.invokeMethod('requestLocationPermission');
    } catch (_) {}
  }

  /// Kiểm tra GPS phần cứng có đang bật không
  Future<bool> isLocationEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>('isLocationEnabled');
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- HỖ TRỢ LƯU CACHE NGOẠI TUYẾN ---
  Future<void> _cacheLastLocation(double lat, double lng) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('careai_last_gps_lat', lat);
      await prefs.setDouble('careai_last_gps_lng', lng);
      await prefs.setString(
          'careai_last_gps_time', DateTime.now().toUtc().toIso8601String());
    } catch (_) {}
  }

  Future<GpsLocationResult?> _getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('careai_last_gps_lat');
      final lng = prefs.getDouble('careai_last_gps_lng');
      final timeStr = prefs.getString('careai_last_gps_time');

      if (lat != null && lng != null) {
        return GpsLocationResult(
          latitude: lat,
          longitude: lng,
          accuracy: null,
          provider: 'cached_offline',
          isRealGps: true,
          timestamp: timeStr != null
              ? DateTime.tryParse(timeStr) ?? DateTime.now().toUtc()
              : DateTime.now().toUtc(),
        );
      }
    } catch (_) {}
    return null;
  }
}
