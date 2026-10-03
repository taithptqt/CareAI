import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

      // 2. Thử gọi kênh native Android nếu chạy trên Android
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
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
              await _cacheLastLocation(lat, lng);
              return result;
            }
          }
        } catch (e) {
          debugPrint('[LocationService] Lỗi kênh Native Android: $e');
        }
      }

      // 3. Sử dụng Geolocator đa nền tảng (phục vụ iOS và Android fallback)
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        final result = GpsLocationResult(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy.isFinite && position.accuracy > 0 ? position.accuracy : null,
          provider: defaultTargetPlatform == TargetPlatform.iOS ? 'ios_corelocation' : 'geolocator',
          isRealGps: !position.isMocked,
          timestamp: position.timestamp.toUtc(),
        );
        await _cacheLastLocation(position.latitude, position.longitude);
        return result;
      } catch (geoError) {
        debugPrint('[LocationService] Lỗi khi lấy GPS qua Geolocator: $geoError');
      }
    } catch (e) {
      debugPrint('[LocationService] Lỗi tổng quát khi lấy GPS: $e');
    }

    // 4. Fallback: Lấy vị trí đã cache trước đó từ bộ nhớ máy
    final cached = await _getCachedLocation();
    if (cached != null) {
      return cached;
    }

    // 5. Fallback cuối cùng: Vị trí mặc định
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
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final success = await _channel.invokeMethod<bool>('openGoogleMaps', {
          'latitude': latitude,
          'longitude': longitude,
          'label': label ?? 'Vị trí người cao tuổi CareAI',
        });
        if (success == true) return true;
      } catch (e) {
        debugPrint('[LocationService] Lỗi gọi openGoogleMaps Android: $e');
      }
    }

    // Fallback đa nền tảng (iOS / Desktop / Web)
    try {
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$latitude,$longitude');
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[LocationService] Lỗi fallback mở Google Maps: $e');
    }
    return false;
  }

  /// Mở chỉ đường cứu nạn trực tiếp tới vị trí tọa độ trên Google Maps (Turn-by-turn Navigation)
  Future<bool> openGoogleMapsDirections(double latitude, double longitude) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final success = await _channel.invokeMethod<bool>('openGoogleMapsDirections', {
          'latitude': latitude,
          'longitude': longitude,
        });
        if (success == true) return true;
      } catch (e) {
        debugPrint('[LocationService] Lỗi gọi openGoogleMapsDirections Android: $e');
      }
    }

    // Fallback đa nền tảng (iOS sử dụng Apple Maps hoặc Google Maps):
    try {
      final appleMapsUri = Uri.parse('https://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d');
      final googleMapsUri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude');
      if (defaultTargetPlatform == TargetPlatform.iOS && await canLaunchUrl(appleMapsUri)) {
        return await launchUrl(appleMapsUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(googleMapsUri)) {
        return await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[LocationService] Lỗi fallback chỉ đường: $e');
    }
    return false;
  }

  /// Kiểm tra quyền truy cập vị trí
  Future<bool> hasLocationPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final hasPerm = await _channel.invokeMethod<bool>('hasLocationPermission');
        if (hasPerm != null) return hasPerm;
      } catch (_) {}
    }

    try {
      final perm = await Geolocator.checkPermission();
      return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Yêu cầu cấp quyền vị trí
  Future<void> requestLocationPermission() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('requestLocationPermission');
        return;
      } catch (_) {}
    }

    try {
      await Geolocator.requestPermission();
    } catch (_) {}
  }

  /// Kiểm tra GPS phần cứng có đang bật không
  Future<bool> isLocationEnabled() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final enabled = await _channel.invokeMethod<bool>('isLocationEnabled');
        if (enabled != null) return enabled;
      } catch (_) {}
    }

    try {
      return await Geolocator.isLocationServiceEnabled();
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
