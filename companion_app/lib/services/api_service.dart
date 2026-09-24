import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_models.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  ApiService._init();

  static const String usbServerUrl = 'http://127.0.0.1:5097';
  static const String internetTunnelUrl = 'https://promote-continue-scholarships-guy.trycloudflare.com';
  static const String wifiServerUrl = 'http://192.168.0.105:5097';

  String _activeServerUrl = usbServerUrl;
  String get activeServerUrl => _activeServerUrl;

  Future<String> getServerUrl() async {
    return _activeServerUrl;
  }

  Future<String?> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id');
  }

  Future<String?> getDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_token');
  }

  Future<String?> getElderName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('elder_name');
  }

  Future<bool> isPaired() async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    return deviceId != null && deviceId.isNotEmpty && deviceToken != null && deviceToken.isNotEmpty;
  }

  /// Ghép nối thiết bị với Backend bằng mã PIN 6 số
  Future<PairDeviceResponse> pairDevice({
    required String serverUrl,
    required String pin,
    String? customDeviceId,
  }) async {
    final normalizedUrl = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final deviceId = customDeviceId ?? 'DEV_${const Uuid().v4().substring(0, 8).toUpperCase()}';

    final requestBody = PairDeviceRequest(
      deviceId: deviceId,
      pairingPin: pin.trim(),
      deviceType: 'SMARTPHONE_COMPANION',
      firmwareVersion: '1.0.0',
    ).toJson();

    final response = await http.post(
      Uri.parse('$normalizedUrl/api/v1/devices/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final pairResponse = PairDeviceResponse.fromJson(json);

      // Lưu trữ cấu hình vào SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server_base_url', normalizedUrl);
      await prefs.setString('device_id', pairResponse.deviceId);
      await prefs.setString('device_token', pairResponse.deviceToken);
      await prefs.setString('elder_profile_id', pairResponse.elderProfileId);
      await prefs.setString('elder_name', pairResponse.fullName);

      _activeServerUrl = normalizedUrl;
      return pairResponse;
    } else {
      String errorMessage = 'Ghép nối thất bại (Mã: ${response.statusCode})';
      try {
        final errJson = jsonDecode(response.body);
        if (errJson is Map && errJson.containsKey('error')) {
          errorMessage = errJson['error'];
        }
      } catch (_) {}
      throw HttpException(errorMessage);
    }
  }

  /// Hủy ghép nối
  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    await prefs.remove('device_token');
    await prefs.remove('elder_profile_id');
    await prefs.remove('elder_name');
  }

  /// Danh sách URL thử nghiệm theo thứ tự ưu tiên chuẩn mực:
  /// Luôn ưu tiên Cáp USB (127.0.0.1:5097) trước vì độ trễ 0ms và không tốn dữ liệu di động.
  /// Nếu Cáp USB không khả dụng, dùng Internet Tunnel, sau đó tới Wi-Fi LAN.
  List<String> _getEndpointsToTry() {
    return [usbServerUrl, internetTunnelUrl, wifiServerUrl];
  }

  /// Gửi tín hiệu SOS Fast-Lane với cơ chế Chuyển mạch Dự phòng Kép (Dual-Failover)
  Future<bool> sendFastLaneSos(SosPacketRequest packet) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();

    if (deviceId == null || deviceToken == null) {
      throw const HttpException('Thiết bị chưa được ghép nối.');
    }

    final headers = {
      'Content-Type': 'application/json',
      'X-DeviceId': deviceId,
      'X-Device-Token': deviceToken,
    };

    final endpoints = _getEndpointsToTry();

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/incidents/sos'),
          headers: headers,
          body: jsonEncode(packet.toJson()),
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {
        // Tự động chuyển mạch sang endpoint dự phòng tiếp theo
      }
    }

    return false;
  }

  /// Gửi dữ liệu viễn trắc định kỳ theo lô (Batch-Lane Ingestion)
  Future<bool> sendBatchTelemetry(String batchId, List<TelemetrySample> samples) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();

    if (deviceId == null || deviceToken == null) {
      throw const HttpException('Thiết bị chưa được ghép nối.');
    }

    final headers = {
      'Content-Type': 'application/json',
      'X-DeviceId': deviceId,
      'X-Device-Token': deviceToken,
    };

    final payload = {
      'batchId': batchId,
      'samples': samples.map((s) => s.toJson()).toList(),
    };

    final endpoints = _getEndpointsToTry();

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/telemetry/ingest'),
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200 || response.statusCode == 201) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Gửi Heartbeat định kỳ
  Future<bool> sendHeartbeat({int? batteryPercentage, bool? onBody}) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();

    if (deviceId == null || deviceToken == null) return false;

    final headers = {
      'Content-Type': 'application/json',
      'X-DeviceId': deviceId,
      'X-Device-Token': deviceToken,
    };

    final body = HeartbeatRequest(
      batteryPercentage: batteryPercentage,
      onBody: onBody,
    ).toJson();

    final endpoints = _getEndpointsToTry();

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/devices/heartbeat'),
          headers: headers,
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Kiểm tra trạng thái máy chủ (/healthz) - Ưu tiên Cáp USB trước, sau đó tới Internet Tunnel, rồi Wi-Fi LAN
  Future<bool> checkServerHealth() async {
    // 1. Thử kênh ưu tiên cao nhất: Cáp USB
    try {
      final response = await http.get(
        Uri.parse('$usbServerUrl/healthz'),
      ).timeout(const Duration(milliseconds: 2000));

      if (response.statusCode == 200) {
        _activeServerUrl = usbServerUrl;
        return true;
      }
    } catch (_) {}

    // 2. Thử kênh đám mây Internet (Hoạt động trên MỌI Wi-Fi & 4G/5G)
    try {
      final response = await http.get(
        Uri.parse('$internetTunnelUrl/healthz'),
      ).timeout(const Duration(milliseconds: 3000));

      if (response.statusCode == 200) {
        _activeServerUrl = internetTunnelUrl;
        return true;
      }
    } catch (_) {}

    // 3. Thử kênh Wi-Fi mạng LAN
    try {
      final response = await http.get(
        Uri.parse('$wifiServerUrl/healthz'),
      ).timeout(const Duration(milliseconds: 2000));

      if (response.statusCode == 200) {
        _activeServerUrl = wifiServerUrl;
        return true;
      }
    } catch (_) {}

    return false;
  }
}
