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

  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  bool _isPhoneFallDetectorEnabled = false;

  // Thuật toán phát hiện ngã dự phòng trên điện thoại
  bool _freeFallDetected = false;
  DateTime? _freeFallTime;

  /// Khởi tạo lắng nghe Fall Bridge từ Native Kotlin (Samsung Galaxy Watch)
  void initialize() {
    _fallChannel.setMethodCallHandler((call) async {
      if (call.method == 'onHardwareFallDetected') {
        final rawMap = Map<String, dynamic>.from(call.arguments as Map);
        final event = FallEvent.fromMap(rawMap, isHardware: true);
        _fallEventController.add(event);
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

  /// Hủy cảnh báo ngã (Người dùng bấm nút "TÔI ỔN")
  /// Gửi lệnh hủy AlarmManager Watchdog sang Native Android
  Future<bool> cancelFallAlarm(String eventId) async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
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
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
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

  /// Kiểm tra quyền SCHEDULE_EXACT_ALARM trên Android 12+
  Future<bool> checkExactAlarmPermission() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final allowed = await _fallChannel.invokeMethod<bool>('checkExactAlarmPermission');
      return allowed ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Kích hoạt mô phỏng sự cố ngã phần cứng Wear OS từ Companion App
  Future<String?> simulateHardwareFall() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final eventId = await _fallChannel.invokeMethod<String>('simulateHardwareFall');
      return eventId;
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _sensorSubscription?.cancel();
    _fallEventController.close();
  }
}
