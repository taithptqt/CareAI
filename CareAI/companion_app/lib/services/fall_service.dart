import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/fall_event.dart';

class FallService {
  static final FallService instance = FallService._init();
  FallService._init();

  static const MethodChannel _fallChannel = MethodChannel('vn.careai.companion/fall_bridge');

  final _fallEventController = StreamController<FallEvent>.broadcast();
  Stream<FallEvent> get onFallDetected => _fallEventController.stream;

  final _manualSosController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onManualSosTriggered => _manualSosController.stream;

  final _watchStatusController = StreamController<WatchStatus>.broadcast();
  Stream<WatchStatus> get onWatchConnectionChanged => _watchStatusController.stream;

  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  bool _isPhoneFallDetectorEnabled = false;

  // Thuật toán phát hiện ngã dự phòng trên điện thoại
  bool _freeFallDetected = false;
  DateTime? _freeFallTime;

  /// Khởi tạo lắng nghe Fall Bridge và Sự kiện kết nối Đồng hồ tức thì từ Native
  void initialize() {
    _fallChannel.setMethodCallHandler((call) async {
      if (call.method == 'onHardwareFallDetected') {
        final rawMap = Map<String, dynamic>.from(call.arguments as Map);
        final event = FallEvent.fromMap(rawMap, isHardware: true);
        _fallEventController.add(event);
      } else if (call.method == 'onManualSosTriggered') {
        final rawMap = Map<String, dynamic>.from(call.arguments as Map);
        _manualSosController.add(rawMap);
      } else if (call.method == 'onWatchConnectionChanged') {
        final rawMap = Map<String, dynamic>.from(call.arguments as Map);
        final status = WatchStatus.fromMap(rawMap);
        _watchStatusController.add(status);
      }
    });
  }

  /// Bật cảm biến gia tốc trên điện thoại làm dự phòng
  void startPhoneAccelerometerDetector() {
    if (_isPhoneFallDetectorEnabled) return;
    _isPhoneFallDetectorEnabled = true;

    _sensorSubscription = accelerometerEventStream().listen((event) {
      _processAccelerometerSample(event.x, event.y, event.z);
    });
  }

  /// Tắt cảm biến dự phòng
  void stopPhoneAccelerometerDetector() {
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    _isPhoneFallDetectorEnabled = false;
  }

  void _processAccelerometerSample(double x, double y, double z) {
    // Tính gia tốc tổng hợp (magnitude)
    final magnitude = sqrt(x * x + y * y + z * z);
    final now = DateTime.now();

    // Pha 1: Trọng lực giảm đột ngột (Rơi tự do - Free Fall: < 4.0 m/s^2)
    if (magnitude < 4.0) {
      _freeFallDetected = true;
      _freeFallTime = now;
      return;
    }

    // Pha 2: Va đập mạnh (Impact: > 28.0 m/s^2 ~ 2.85G) xảy ra trong vòng 800ms sau pha rơi
    if (_freeFallDetected && _freeFallTime != null) {
      if (now.difference(_freeFallTime!).inMilliseconds <= 800) {
        if (magnitude > 28.0) {
          _freeFallDetected = false;
          _freeFallTime = null;

          final impactG = magnitude / 9.81;
          final eventId = 'FALL_PHONE_${now.millisecondsSinceEpoch}';

          final event = FallEvent(
            eventId: eventId,
            timestamp: now.millisecondsSinceEpoch,
            impactG: double.parse(impactG.toStringAsFixed(2)),
            secondsRemaining: 30,
            isFromHardwareWatch: false,
          );

          _fallEventController.add(event);
        }
      } else {
        // Quá hạn 800ms -> Hủy cờ rơi tự do
        _freeFallDetected = false;
        _freeFallTime = null;
      }
    }
  }

  bool get _isSupportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Hủy cảnh báo ngã (Người dùng bấm nút "TÔI ỔN")
  /// Gửi lệnh hủy Watchdog Alarm sang Native Android / iOS
  Future<bool> cancelFallAlarm(String eventId) async {
    if (!_isSupportedPlatform) {
      return false;
    }
    try {
      final success = await _fallChannel.invokeMethod<bool>('cancelFallAlarm', {
        'eventId': eventId,
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Dừng âm thanh còi hú y tế khẩn cấp
  Future<bool> stopEmergencySound([String? eventId]) async {
    if (!_isSupportedPlatform) {
      return false;
    }
    try {
      final args = <String, dynamic>{};
      if (eventId != null) {
        args['eventId'] = eventId;
      }
      final success = await _fallChannel.invokeMethod<bool>('stopEmergencySound', args);
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra quyền SCHEDULE_EXACT_ALARM trên Android 12+ (trên iOS luôn true)
  Future<bool> checkExactAlarmPermission() async {
    if (!_isSupportedPlatform) {
      return true;
    }
    try {
      final allowed = await _fallChannel.invokeMethod<bool>('checkExactAlarmPermission');
      return allowed ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Kích hoạt mô phỏng sự cố ngã phần cứng từ Companion App (Wear OS hoặc watchOS)
  Future<String?> simulateHardwareFall() async {
    if (!_isSupportedPlatform) {
      return null;
    }
    try {
      final eventId = await _fallChannel.invokeMethod<String>('simulateHardwareFall');
      return eventId;
    } catch (e) {
      return null;
    }
  }

  /// Lấy trạng thái kết nối thực tế tới Wear OS (Galaxy Watch) hoặc watchOS (Apple Watch)
  Future<WatchStatus> getConnectedWatchStatus() async {
    if (!_isSupportedPlatform) {
      return const WatchStatus(isConnected: false);
    }
    try {
      final res = await _fallChannel.invokeMethod<Map<dynamic, dynamic>>('getConnectedWatchStatus');
      debugPrint('[FallService] getConnectedWatchStatus raw result: $res');
      if (res != null) {
        return WatchStatus.fromMap(res);
      }
      return const WatchStatus(isConnected: false);
    } catch (e, stack) {
      debugPrint('[FallService] getConnectedWatchStatus error: $e\n$stack');
      return WatchStatus(isConnected: false, error: e.toString());
    }
  }

  /// Đồng bộ thông tin xác thực lên phần cứng đồng hồ (Galaxy Watch qua Wear OS Data Layer, Apple Watch qua WCSession)
  Future<bool> syncWatchCredentials({
    required String backendUrl,
    required String deviceId,
    required String deviceToken,
    String? elderName,
  }) async {
    if (!_isSupportedPlatform) {
      return false;
    }
    try {
      final success = await _fallChannel.invokeMethod<bool>('syncWatchCredentials', {
        'backendUrl': backendUrl,
        'deviceId': deviceId,
        'deviceToken': deviceToken,
        'elderName': elderName ?? '',
      });
      return success ?? false;
    } catch (e) {
      debugPrint('[FallService] Lỗi đồng bộ thông tin xác thực sang đồng hồ: $e');
      return false;
    }
  }

  /// Gửi lệnh hủy ghép nối đồng hồ ngoại vi (Apple Watch qua WCSession, Galaxy Watch qua Wearable DataClient)
  Future<bool> unpairWatch() async {
    if (!_isSupportedPlatform) {
      return true;
    }
    try {
      final success = await _fallChannel.invokeMethod<bool>('unpairWatch');
      return success ?? false;
    } catch (e) {
      debugPrint('[FallService] Lỗi khi gửi lệnh unpairWatch: $e');
      return false;
    }
  }

  /// Thông báo trạng thái phản hồi sự cố khẩn cấp sang Apple Watch / Wear OS (Closed-Loop Feedback)
  Future<bool> notifyIncidentStatusToWatch({
    required String status,
    String? acknowledgedByName,
    String? notes,
    String? incidentId,
  }) async {
    if (!_isSupportedPlatform) {
      return false;
    }
    try {
      final success = await _fallChannel.invokeMethod<bool>('notifyIncidentStatusToWatch', {
        'status': status,
        'acknowledgedByName': acknowledgedByName ?? '',
        'notes': notes ?? '',
        'incidentId': incidentId ?? '',
      });
      return success ?? false;
    } catch (e) {
      debugPrint('[FallService] Lỗi gửi trạng thái sự cố sang đồng hồ: $e');
      return false;
    }
  }

  void dispose() {
    _sensorSubscription?.cancel();
    _fallEventController.close();
    _manualSosController.close();
    _watchStatusController.close();
  }
}

/// Trạng thái kết nối phần cứng đồng hồ Wear OS (Galaxy Watch) hoặc watchOS (Apple Watch)
class WatchStatus {
  final bool isConnected;
  final String? watchName;
  final String? nodeId;
  final bool isNearby;
  final int connectedCount;
  final String? error;
  final String? reason;
  final bool isPaired;
  final bool isWatchAppInstalled;
  final bool? isWorn; // true = trên cổ tay, false = tháo ra, null = chưa xác định
  final bool? isCharging; // true = đang cắm sạc, false = không sạc, null = chưa xác định
  final int? batteryLevel; // 0 - 100%, null = chưa xác định

  const WatchStatus({
    required this.isConnected,
    this.watchName,
    this.nodeId,
    this.isNearby = false,
    this.connectedCount = 0,
    this.error,
    this.reason,
    this.isPaired = false,
    this.isWatchAppInstalled = false,
    this.isWorn,
    this.isCharging,
    this.batteryLevel,
  });

  factory WatchStatus.fromMap(Map<dynamic, dynamic> map) {
    final isConnected = map['isConnected'] as bool? ?? false;
    return WatchStatus(
      isConnected: isConnected,
      watchName: map['watchName'] as String?,
      nodeId: map['nodeId'] as String?,
      isNearby: map['isNearby'] as bool? ?? false,
      connectedCount: map['connectedCount'] as int? ?? 0,
      error: map['error'] as String?,
      reason: map['reason'] as String?,
      isPaired: map['isPaired'] as bool? ?? isConnected,
      isWatchAppInstalled: map['isWatchAppInstalled'] as bool? ?? false,
      isWorn: map['isWorn'] as bool?,
      isCharging: map['isCharging'] as bool?,
      batteryLevel: map['batteryLevel'] as int?,
    );
  }
}
