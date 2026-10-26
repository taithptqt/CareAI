import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/device_models.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';
import 'fall_service.dart';
import 'local_offline_store.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  ApiService._init();

  final deviceUnpairedNotifier = ValueNotifier<bool>(false);

  static const String internetTunnelUrl = 'https://careai-hweuawcug0eehucf.southeastasia-01.azurewebsites.net';
  static const String usbServerUrl = 'http://127.0.0.1:5097';
  static const String wifiServerUrl = 'http://192.168.0.105:5097';

  String _activeServerUrl = internetTunnelUrl;
  String get activeServerUrl => _activeServerUrl;

  Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final isExplicit = prefs.getBool('elder_server_url_explicitly_set') ?? false;
    final saved = prefs.getString('server_base_url');
    if (saved != null && saved.isNotEmpty) {
      if (!isExplicit && saved == usbServerUrl) {
        _activeServerUrl = internetTunnelUrl;
        await prefs.setString('server_base_url', internetTunnelUrl);
        return internetTunnelUrl;
      }
      _activeServerUrl = saved;
      return saved;
    }
    return _activeServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _activeServerUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_base_url', normalized);
    await prefs.setBool('elder_server_url_explicitly_set', true);
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

  Future<String?> getElderProfileId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('elder_profile_id');
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

      // Xóa sạch hàng đợi ngoại tuyến cũ để tránh ô nhiễm dữ liệu sinh hiệu sang Cụ mới
      try {
        await LocalOfflineStore.instance.clearPendingPackets();
      } catch (_) {}

      // Tự động đẩy thông tin xác thực sang đồng hồ Wear OS (Galaxy Watch) / watchOS (Apple Watch)
      try {
        unawaited(FallService.instance.syncWatchCredentials(
          backendUrl: normalizedUrl,
          deviceId: pairResponse.deviceId,
          deviceToken: pairResponse.deviceToken,
          elderName: pairResponse.fullName,
        ));
      } catch (_) {}

      return pairResponse;
    } else {
      throw HttpException(_extractDeviceError(response.body, response.statusCode));
    }
  }

  String _extractDeviceError(String responseBody, int statusCode) {
    final trimmed = responseBody.trim();
    if (trimmed.isEmpty) {
      return _defaultDeviceErrorForStatus(statusCode);
    }

    if (trimmed.startsWith('<') || trimmed.contains('<html') || trimmed.contains('<!DOCTYPE')) {
      final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(trimmed);
      final pageTitle = titleMatch?.group(1)?.trim();
      if (pageTitle != null && pageTitle.isNotEmpty && !pageTitle.toLowerCase().contains('error')) {
        return '$pageTitle (Mã: $statusCode)';
      }
      return _defaultDeviceErrorForStatus(statusCode);
    }

    try {
      final data = jsonDecode(trimmed);
      if (data is Map) {
        if (data['detail'] != null && data['detail'].toString().trim().isNotEmpty) {
          return data['detail'].toString().trim();
        }
        if (data['error'] != null && data['error'].toString().trim().isNotEmpty) {
          return data['error'].toString().trim();
        }
        if (data['message'] != null && data['message'].toString().trim().isNotEmpty) {
          return data['message'].toString().trim();
        }
        if (data['title'] != null && data['title'].toString().trim().isNotEmpty) {
          return data['title'].toString().trim();
        }
      }
    } catch (_) {}

    return _defaultDeviceErrorForStatus(statusCode, fallbackText: trimmed);
  }

  String _defaultDeviceErrorForStatus(int statusCode, {String? fallbackText}) {
    if (fallbackText != null && fallbackText.isNotEmpty && fallbackText.length < 120 && !fallbackText.startsWith('<')) {
      return fallbackText;
    }
    switch (statusCode) {
      case 400:
        return 'Thông tin yêu cầu không hợp lệ hoặc thiếu dữ liệu (Mã 400).';
      case 401:
        return 'Xác thực thiết bị thất bại hoặc token không hợp lệ (Mã 401).';
      case 404:
        return 'Mã PIN ghép nối không tồn tại hoặc đã hết hạn (Mã 404).';
      case 409:
        return 'Thiết bị đã tồn tại hoặc đang có phiên xung đột (Mã 409).';
      case 500:
        return 'Máy chủ nội bộ hoặc cơ sở dữ liệu gặp sự cố (Mã 500). Vui lòng thử lại sau.';
      case 502:
        return 'Cổng kết nối máy chủ không khả dụng (Bad Gateway 502).';
      case 503:
        return 'Cơ sở dữ liệu đám mây đang tạm dừng hoặc máy chủ đang bảo trì (Mã 503).';
      case 504:
        return 'Hết thời gian chờ phản hồi từ máy chủ (Gateway Timeout 504).';
      default:
        return 'Yêu cầu thất bại với mã lỗi HTTP $statusCode.';
    }
  }

  /// Hủy ghép nối
  Future<void> unpair() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
    await prefs.remove('device_token');
    await prefs.remove('elder_profile_id');
    await prefs.remove('elder_name');
    await prefs.remove('last_paired_watch_name');

    // Dọn sạch hàng đợi ngoại tuyến khi hủy ghép nối
    try {
      await LocalOfflineStore.instance.clearPendingPackets();
    } catch (_) {}

    // Đồng bộ hủy thông tin xác thực trên đồng hồ
    try {
      unawaited(FallService.instance.unpairWatch());
      unawaited(FallService.instance.syncWatchCredentials(
        backendUrl: '',
        deviceId: '',
        deviceToken: '',
        elderName: '',
      ));
    } catch (_) {}
  }

  /// Đồng bộ tên và trạng thái kết nối của đồng hồ thông minh lên máy chủ
  Future<bool> syncConnectedWatch(
    String watchModel, {
    bool isConnected = true,
    String? disconnectReason,
    bool? isWorn,
    bool? isCharging,
    int? batteryLevel,
    int? todaySteps,
    double? heartRate,
    double? spo2,
    double? bpSystolic,
    double? bpDiastolic,
    int? sleepMinutes,
    int? deepSleepMinutes,
    int? coreSleepMinutes,
    int? remSleepMinutes,
    int? awakeMinutes,
    int? wakeCount,
    double? minSleepingHr,
    double? avgSleepingHr,
    double? minNightSpo2,
    int? nightSpo2DipsCount,
    String? breathingDisturbances,
    List<String>? supportedMetrics,
  }) async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    if (deviceId == null || deviceToken == null) return false;

    final headers = {
      'Content-Type': 'application/json',
      'X-DeviceId': deviceId,
      'X-Device-Token': deviceToken,
    };
    final bodyMap = <String, dynamic>{
      'watchModel': watchModel,
      'isConnected': isConnected,
    };
    if (disconnectReason != null) {
      bodyMap['disconnectReason'] = disconnectReason;
    }
    if (isWorn != null) {
      bodyMap['isWorn'] = isWorn;
    }
    if (isCharging != null) {
      bodyMap['isCharging'] = isCharging;
    }
    if (batteryLevel != null) {
      bodyMap['batteryLevel'] = batteryLevel;
    }
    if (todaySteps != null && todaySteps > 0) {
      bodyMap['todaySteps'] = todaySteps;
    }
    if (heartRate != null && heartRate > 0) {
      bodyMap['heartRate'] = heartRate;
    }
    if (spo2 != null && spo2 > 0) {
      bodyMap['spo2'] = spo2;
    }
    if (bpSystolic != null && bpSystolic > 0) {
      bodyMap['bpSystolic'] = bpSystolic;
    }
    if (bpDiastolic != null && bpDiastolic > 0) {
      bodyMap['bpDiastolic'] = bpDiastolic;
    }
    if (sleepMinutes != null && sleepMinutes > 0) {
      bodyMap['sleepMinutes'] = sleepMinutes;
    }
    if (deepSleepMinutes != null && deepSleepMinutes > 0) {
      bodyMap['deepSleepMinutes'] = deepSleepMinutes;
    }
    if (coreSleepMinutes != null && coreSleepMinutes > 0) {
      bodyMap['coreSleepMinutes'] = coreSleepMinutes;
    }
    if (remSleepMinutes != null && remSleepMinutes > 0) {
      bodyMap['remSleepMinutes'] = remSleepMinutes;
    }
    if (awakeMinutes != null && awakeMinutes > 0) {
      bodyMap['awakeMinutes'] = awakeMinutes;
    }
    if (wakeCount != null && wakeCount > 0) {
      bodyMap['wakeCount'] = wakeCount;
    }
    if (minSleepingHr != null && minSleepingHr > 0) {
      bodyMap['minSleepingHr'] = minSleepingHr;
    }
    if (avgSleepingHr != null && avgSleepingHr > 0) {
      bodyMap['avgSleepingHr'] = avgSleepingHr;
    }
    if (minNightSpo2 != null && minNightSpo2 > 0) {
      bodyMap['minNightSpo2'] = minNightSpo2;
    }
    if (nightSpo2DipsCount != null && nightSpo2DipsCount > 0) {
      bodyMap['nightSpo2DipsCount'] = nightSpo2DipsCount;
    }
    if (breathingDisturbances != null && breathingDisturbances.isNotEmpty) {
      bodyMap['breathingDisturbances'] = breathingDisturbances;
    }
    if (supportedMetrics != null && supportedMetrics.isNotEmpty) {
      bodyMap['supportedMetrics'] = supportedMetrics;
    }
    final body = jsonEncode(bodyMap);
    final endpoints = _getEndpointsToTry();

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/devices/sync-watch'),
          headers: headers,
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final serverBat = (data['batteryLevel'] as num?)?.toInt();
            final serverWorn = data['isWorn'] as bool?;
            final serverCharging = data['isCharging'] as bool?;
            final prefs = await SharedPreferences.getInstance();
            if (serverBat != null) {
              await prefs.setInt('last_watch_battery_level', serverBat);
            }
            if (serverWorn != null) {
              await prefs.setBool('last_watch_is_worn', serverWorn);
            }
            if (serverCharging != null) {
              await prefs.setBool('last_watch_is_charging', serverCharging);
            }
          } catch (_) {}
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  /// Lấy thông tin trạng thái đồng hồ mới nhất từ máy chủ (pin, sạc, đeo)
  Future<Map<String, dynamic>?> fetchWatchStatusFromServer() async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    if (deviceId == null || deviceToken == null) return null;

    final headers = {
      'Content-Type': 'application/json',
      'X-DeviceId': deviceId,
      'X-Device-Token': deviceToken,
    };
    final prefs = await SharedPreferences.getInstance();
    final watchModel = prefs.getString('last_paired_watch_name') ?? 'Apple Watch';
    final body = jsonEncode({
      'watchModel': watchModel,
      'isConnected': true,
    });
    final endpoints = _getEndpointsToTry();

    for (final url in endpoints) {
      try {
        final response = await http.post(
          Uri.parse('$url/api/v1/devices/sync-watch'),
          headers: headers,
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final serverBat = (data['batteryLevel'] as num?)?.toInt();
          final serverWorn = data['isWorn'] as bool?;
          final serverCharging = data['isCharging'] as bool?;
          if (serverBat != null) {
            await prefs.setInt('last_watch_battery_level', serverBat);
          }
          if (serverWorn != null) {
            await prefs.setBool('last_watch_is_worn', serverWorn);
          }
          if (serverCharging != null) {
            await prefs.setBool('last_watch_is_charging', serverCharging);
          }
          return data;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Danh sách URL thử nghiệm theo thứ tự ưu tiên:
  /// Ưu tiên Đám Mây Azure (Internet 24/7), sau đó chuyển tiếp sang Cáp USB và Wi-Fi LAN.
  List<String> _getEndpointsToTry() {
    return {
      if (_activeServerUrl.isNotEmpty) _activeServerUrl,
      internetTunnelUrl,
      usbServerUrl,
      wifiServerUrl,
    }.toList();
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

    final validSamples = samples.where((s) => s.value > 0 && s.value.isFinite).toList();
    if (validSamples.isEmpty) {
      return true;
    }

    final payload = {
      'batchId': batchId,
      'samples': validSamples.map((s) => s.toJson()).toList(),
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
          try {
            final data = jsonDecode(response.body);
            if (data is Map && data['elderName'] != null) {
              final newName = data['elderName'].toString().trim();
              if (newName.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                final currentName = prefs.getString('elder_name');
                if (currentName != newName) {
                  await prefs.setString('elder_name', newName);
                  unawaited(FallService.instance.syncWatchCredentials(
                    backendUrl: url,
                    deviceId: deviceId,
                    deviceToken: deviceToken,
                    elderName: newName,
                  ));
                }
              }
            }
          } catch (_) {}
          return true;
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          // Thiết bị đã bị vô hiệu hóa hoặc hủy ghép nối từ xa
          await unpair();
          deviceUnpairedNotifier.value = true;
          return false;
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
          try {
            final data = jsonDecode(response.body);
            if (data is Map<String, dynamic> && data['requiresForceSync'] == true) {
              debugPrint('[FORCE-SYNC] Nhận cờ requiresForceSync qua heartbeat. Ép đồng hồ làm tươi dữ liệu.');
              unawaited(FallService.instance.requestWatchForceSync());
            }
          } catch (_) {}
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Kiểm tra trạng thái máy chủ (/healthz) - Ưu tiên Đám mây Azure trước, sau đó tới Cáp USB (nếu cắm), rồi Wi-Fi LAN
  Future<bool> checkServerHealth() async {
    final prefs = await SharedPreferences.getInstance();
    final pairedUrl = prefs.getString('server_base_url');

    final endpoints = {
      if (pairedUrl != null && pairedUrl.isNotEmpty) pairedUrl,
      internetTunnelUrl,
      usbServerUrl,
      wifiServerUrl,
    };

    for (final url in endpoints) {
      try {
        final timeoutMs = url.contains('127.0.0.1') ? 800 : 3000;
        final res = await http.get(Uri.parse('$url/healthz')).timeout(Duration(milliseconds: timeoutMs));
        if (res.statusCode == 200) {
          _activeServerUrl = url;
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  /// Kiểm tra nhanh trạng thái một URL cụ thể
  Future<bool> checkHealth(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await http.get(Uri.parse('$normalized/healthz')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra trạng thái phản hồi sự cố khẩn cấp dành cho thiết bị người già (Closed-Loop Feedback)
  Future<DeviceActiveIncidentResponse?> getActiveIncident() async {
    final deviceId = await getDeviceId();
    final deviceToken = await getDeviceToken();
    if (deviceId == null || deviceToken == null || deviceId.isEmpty || deviceToken.isEmpty) {
      return null;
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
        final res = await http.get(
          Uri.parse('$url/api/v1/devices/active-incident'),
          headers: headers,
        ).timeout(const Duration(seconds: 3));

        if (res.statusCode == 200) {
          _activeServerUrl = url;
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          return DeviceActiveIncidentResponse.fromJson(json);
        }
      } catch (_) {}
    }

    return null;
  }
}
