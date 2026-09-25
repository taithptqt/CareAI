import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_models.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  ApiService._init();

  static const String usbServerUrl = 'http://127.0.0.1:5097';
  static const String internetTunnelUrl = 'https://recording-arthur-widely-bald.trycloudflare.com';
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
    return (await sendFastLaneSosWithResult(packet)).accepted;
  }

  Future<({bool accepted, String? incidentId})> sendFastLaneSosWithResult(
      SosPacketRequest packet) async {
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

    final prefs = await SharedPreferences.getInstance();
    final pairedUrl = prefs.getString('server_base_url');
    final endpoints = {
      if (pairedUrl != null && pairedUrl.isNotEmpty) pairedUrl,
      _activeServerUrl,
      ..._getEndpointsToTry(),
    };

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/incidents/sos'),
          headers: headers,
          body: jsonEncode(packet.toJson()),
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          _activeServerUrl = url;
          final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
          return (accepted: true, incidentId: responseBody['incidentId'] as String?);
        }
      } catch (_) {
        // Tự động chuyển mạch sang endpoint dự phòng tiếp theo
      }
    }

    return (accepted: false, incidentId: null);
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
          Uri.parse('$url/api/v1/telemetry/batch'),
          headers: headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Gửi ngay mẫu tim nguy kịch; packetId được giữ nguyên khi thử lại từ SQLite.
  Future<bool> sendUrgentHeartRate(String packetId, TelemetrySample sample) async {
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
    final body = jsonEncode({
      'packetId': packetId,
      'heartRateBpm': sample.value,
      'timestamp': sample.timestamp.toUtc().toIso8601String(),
    });
    final prefs = await SharedPreferences.getInstance();
    final pairedServerUrl = prefs.getString('server_base_url');
    final endpoints = {
      if (pairedServerUrl != null && pairedServerUrl.isNotEmpty) pairedServerUrl,
      _activeServerUrl,
      ..._getEndpointsToTry(),
    };

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/telemetry/urgent-heart-rate'),
          headers: headers,
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200 || response.statusCode == 201) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {
        // Cùng packetId được gửi lại qua kênh tiếp theo hoặc hàng đợi offline.
      }
    }

    return false;
  }

  Future<bool> uploadIncidentPhoto(String incidentId, Uint8List jpeg,
      DateTime capturedAt) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    if (deviceId == null || deviceToken == null || jpeg.isEmpty || jpeg.length > 1000000) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final pairedUrl = prefs.getString('server_base_url');
    final endpoints = {
      if (pairedUrl != null && pairedUrl.isNotEmpty) pairedUrl,
      _activeServerUrl,
      ..._getEndpointsToTry(),
    };
    for (final url in endpoints) {
      try {
        final request = http.MultipartRequest('POST',
            Uri.parse('$url/api/v1/incidents/${Uri.encodeComponent(incidentId)}/photo'));
        request.headers['X-DeviceId'] = deviceId;
        request.headers['X-Device-Token'] = deviceToken;
        request.fields['capturedAt'] = capturedAt.toUtc().toIso8601String();
        request.files.add(http.MultipartFile.fromBytes('photo', jpeg,
          filename: 'incident.jpg', contentType: MediaType('image', 'jpeg')));
        final response = await http.Response.fromStream(
            await request.send().timeout(const Duration(seconds: 8)));
        if (response.statusCode == 200 || response.statusCode == 201) {
          _activeServerUrl = url;
          return true;
        }
        if (response.statusCode >= 400 && response.statusCode < 500) return false;
      } catch (_) {}
    }
    return false;
  }

  Future<bool> attachIncidentLocation(
      String incidentId, String coordinates, DateTime capturedAt,
      {bool isSimulated = false, double? accuracyMeters}) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    if (deviceId == null || deviceToken == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final pairedUrl = prefs.getString('server_base_url');
    final endpoints = {
      if (pairedUrl != null && pairedUrl.isNotEmpty) pairedUrl,
      _activeServerUrl,
      ..._getEndpointsToTry(),
    };
    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/incidents/${Uri.encodeComponent(incidentId)}/location'),
          headers: {
            'Content-Type': 'application/json',
            'X-DeviceId': deviceId,
            'X-Device-Token': deviceToken,
          },
          body: jsonEncode({
            'coordinates': coordinates,
            'capturedAt': capturedAt.toUtc().toIso8601String(),
            'isSimulated': isSimulated,
            'accuracyMeters': accuracyMeters,
          }),
        ).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          _activeServerUrl = url;
          return true;
        }
        if (response.statusCode >= 400 && response.statusCode < 500) return false;
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
