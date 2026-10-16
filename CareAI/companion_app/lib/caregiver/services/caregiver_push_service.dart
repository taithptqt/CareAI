import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/role_selection_screen.dart';
import '../screens/incident_detail_screen.dart';
import 'caregiver_api_service.dart';

@pragma('vm:entry-point')
Future<void> caregiverBackgroundMessage(RemoteMessage message) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(RoleSelectionScreen.prefSelectedRole) != 'caregiver' ||
      (prefs.getString('jwt_token') ?? '').isEmpty) {
    return;
  }
  await dispatchNativeCaregiverAlert(message);
}

@visibleForTesting
Future<void> dispatchNativeCaregiverAlert(RemoteMessage message,
    {Future<void> Function(Map<String, dynamic>)? sendNative}) async {
  final data = message.data;
  final incidentId = data['incidentId'];
  if (incidentId == null || incidentId.isEmpty) return;
  final urgent = data['siren']?.toLowerCase() == 'true';
  final isHighPriority = data['priority']?.toUpperCase() == 'HIGH' || data['priority']?.toUpperCase() == 'CRITICAL';
  final eventType = data['eventType']?.toUpperCase() ?? '';
  if (!urgent && !isHighPriority && eventType != 'ACKNOWLEDGED' && eventType != 'RESOLVED') return;
  final arguments = <String, dynamic>{
    'incidentId': incidentId,
    'alertCycleNumber': int.tryParse(data['alertCycleNumber'] ?? '') ?? 1,
    'eventType': eventType,
    'title': data['title'] ?? 'CẢNH BÁO CẤP CỨU',
    'body': data['body'] ?? 'Người cao tuổi cần trợ giúp ngay.',
    'emergencyType': data['emergencyType'] ?? '',
    'priority': data['priority'] ?? '',
    'siren': urgent,
  };
  if (sendNative != null) {
    await sendNative(arguments);
    return;
  }
  await dispatchDirectCaregiverAlert(arguments);
}

Future<void> dispatchDirectCaregiverAlert(Map<String, dynamic> arguments) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await AndroidIntent(
      action: 'vn.careai.companion.ACTION_CAREGIVER_ALERT',
      package: 'vn.careai.companion',
      arguments: arguments,
    ).sendBroadcast();
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    const alarm = MethodChannel('vn.careai.companion/caregiver_alarm');
    try {
      if (arguments['eventType'] == 'ACKNOWLEDGED' || arguments['eventType'] == 'RESOLVED') {
        await alarm.invokeMethod('stop', arguments);
      } else {
        await alarm.invokeMethod('start', arguments);
      }
    } catch (_) {}
  }
}

class CaregiverPushService {
  CaregiverPushService._();
  static final instance = CaregiverPushService._();

  static const _apiKey = String.fromEnvironment('CAREAI_FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('CAREAI_FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment('CAREAI_FIREBASE_SENDER_ID');
  static const _projectId = String.fromEnvironment('CAREAI_FIREBASE_PROJECT_ID');
  static const _alertChannel = MethodChannel('vn.careai.companion/caregiver_alert');

  final navigatorKey = GlobalKey<NavigatorState>();
  final _events = StreamController<String>.broadcast();
  Stream<String> get incidentsChanged => _events.stream;
  bool _ready = false;
  String? _pendingIncidentId;
  String? visibleIncidentId;
  Timer? _fallbackPollingTimer;
  final Set<String> _alertedIncidentCycles = {};

  void _startFallbackPolling() {
    _fallbackPollingTimer?.cancel();
    _fallbackPollingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _checkActiveIncidentsFallback();
    });
    unawaited(_checkActiveIncidentsFallback());
  }

  Future<void> _checkActiveIncidentsFallback() async {
    if (!await _isCaregiver()) return;
    try {
      final list = await CaregiverApiService.instance.getActiveIncidents();
      final currentOpenIds = <String>{};

      for (final inc in list) {
        if (!inc.isOpen) continue;
        final isCritical = inc.severity == 'Critical' || inc.emergencyType == 'FALL';
        if (!isCritical) continue;

        currentOpenIds.add(inc.id);
        final cycle = inc.alertState?.cycleNumber ?? 1;
        final key = '${inc.id}_$cycle';

        if (!_alertedIncidentCycles.contains(key)) {
          _alertedIncidentCycles.add(key);
          debugPrint('[CareAI-Push] Fallback Polling: Phát hiện sự cố khẩn cấp ${inc.id} ($key). Kích hoạt báo động...');

          await dispatchDirectCaregiverAlert({
            'incidentId': inc.id,
            'alertCycleNumber': cycle,
            'eventType': inc.emergencyType,
            'title': 'CẢNH BÁO CẤP CỨU',
            'body': 'Người cao tuổi cần trợ giúp ngay (${inc.emergencyType}).',
            'emergencyType': inc.emergencyType,
            'priority': 'CRITICAL',
            'siren': true,
          });

          // Vũ trang AlarmManager cho native Android để chạy độc lập khi app background/tắt
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
            const MethodChannel('vn.careai.companion/fall_bridge')
                .invokeMethod('armCaregiverBackgroundWatchdog')
                .catchError((_) => null);
          }
        }
      }

      // Xóa các sự cố không còn mở khỏi danh sách đã cảnh báo
      _alertedIncidentCycles.removeWhere((k) {
        final id = k.split('_').first;
        return !currentOpenIds.contains(id);
      });
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      _alertChannel.setMethodCallHandler((call) async {
        if (call.method == 'openIncident') {
          final id = call.arguments as String?;
          if (id != null && id.isNotEmpty) {
            _pendingIncidentId = id;
            await openPendingIncident();
          }
        }
      });
      try {
        final id = await _alertChannel.invokeMethod<String>('getPendingIncident');
        if (id != null && id.isNotEmpty) {
          _pendingIncidentId = id;
          await openPendingIncident();
        }
      } catch (_) {}
    }

    // Khởi động Fallback Polling liên tục song song để bảo đảm nhận cảnh báo ngay cả khi Firebase chưa cấu hình hoặc bị chặn
    _startFallbackPolling();

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) ||
        _apiKey.isEmpty || _appId.isEmpty || _senderId.isEmpty || _projectId.isEmpty) {
      debugPrint('[CareAI-Push] Firebase chưa được cấu hình. Đang chạy cơ chế giám sát sự cố nền độc lập.');
      return;
    }
    try {
      await Firebase.initializeApp(options: const FirebaseOptions(
        apiKey: _apiKey, appId: _appId,
        messagingSenderId: _senderId, projectId: _projectId,
      ));
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        FirebaseMessaging.onBackgroundMessage(caregiverBackgroundMessage);
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );
      FirebaseMessaging.onMessage.listen((message) {
        unawaited(_handleMessage(message, openScreen: true));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        unawaited(_handleMessage(message, openScreen: true, openedFromNotification: true));
      });
      messaging.onTokenRefresh.listen((token) {
        unawaited(_register(token));
      });
      _ready = true;
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        await _handleMessage(initial,
          openScreen: true, openedFromNotification: true);
      }
      await registerCurrentToken();
    } catch (error) {
      debugPrint('[CareAI-Push] Không thể khởi tạo thông báo: $error');
    }
  }

  Future<void> registerCurrentToken() async {
    if (!_ready || !await _isCaregiver()) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _register(token);
      await openPendingIncident();
    } catch (error) {
      debugPrint('[CareAI-Push] Không thể lấy token: $error');
    }
  }

  Future<void> _register(String token) async {
    if (!await _isCaregiver()) return;
    try {
      await CaregiverApiService.instance.registerPushToken(token);
    } catch (error) {
      debugPrint('[CareAI-Push] Đăng ký token thất bại: $error');
    }
  }

  Future<void> unregisterCurrentToken() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await CaregiverApiService.instance.unregisterPushToken(token);
    } catch (error) {
      debugPrint('[CareAI-Push] Hủy token thất bại: $error');
    }
  }

  Future<bool> _isCaregiver() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(RoleSelectionScreen.prefSelectedRole) == 'caregiver' &&
        await CaregiverApiService.instance.isLoggedIn();
  }

  Future<void> _handleMessage(RemoteMessage message,
      {required bool openScreen, bool openedFromNotification = false}) async {
    final id = message.data['incidentId'];
    if (id == null || id.isEmpty || !await _isCaregiver()) return;
    await dispatchNativeCaregiverAlert(message);
    _events.add(id);
    if (openedFromNotification && message.data['siren']?.toLowerCase() != 'true') {
      _pendingIncidentId = id;
      await openPendingIncident();
      return;
    }
    if (message.data['eventType'] == 'PHOTO_AVAILABLE') {
      if (openedFromNotification) {
        _pendingIncidentId = id;
        await openPendingIncident();
      }
      return;
    }
    if (message.data['siren']?.toLowerCase() != 'true') {
      if (openScreen) {
        final context = navigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(message.data['body'] ?? 'Có chỉ số sức khỏe cần kiểm tra.'),
            action: SnackBarAction(
              label: 'Xem',
              onPressed: () {
                _pendingIncidentId = id;
                unawaited(openPendingIncident());
              },
            ),
          ));
        }
      }
      return;
    }
    if (openScreen) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _alertChannel.invokeMethod<void>('showAlarmScreen', <String, dynamic>{
            'incidentId': id,
            'alertCycleNumber': int.tryParse(message.data['alertCycleNumber'] ?? '') ?? 1,
            'title': message.data['title'] ?? 'CẢNH BÁO CẤP CỨU',
            'body': message.data['body'] ?? 'Người cao tuổi cần trợ giúp ngay.',
            'emergencyType': message.data['emergencyType'] ?? '',
          });
        } catch (error) {
          debugPrint('[CareAI-Push] Không thể mở màn hình báo động: $error');
        }
      } else {
        // Trên iOS hoặc môi trường không hỗ trợ Activity đè màn hình khóa:
        // Tự động điều hướng trực tiếp tới màn hình chi tiết sự cố cấp cứu ngay khi nhận cảnh báo
        _pendingIncidentId = id;
        await openPendingIncident();
      }
    }
  }

  Future<void> openPendingIncident() async {
    final id = _pendingIncidentId;
    if (id == null || visibleIncidentId == id || !await _isCaregiver()) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final incident = await CaregiverApiService.instance.getIncident(id);
      _pendingIncidentId = null;
      if (incident.isResolved) return;
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => IncidentDetailScreen(incident: incident),
      ));
    } catch (error) {
      debugPrint('[CareAI-Push] Không thể mở sự cố $id: $error');
    }
  }
}
