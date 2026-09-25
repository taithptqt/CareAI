import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'caregiver_api_service.dart';

class ReportPushService {
  static final instance = ReportPushService._();
  ReportPushService._();
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opened;
  StreamSubscription<RemoteMessage>? _foreground;
  bool _ready = false;
  int _generation = 0;

  Future<void> start(void Function(Map<String, dynamic>) onOpen, VoidCallback onForeground) async {
    const enabled = bool.fromEnvironment('CAREAI_FIREBASE_ENABLED');
    if (!enabled) return;
    final generation = ++_generation;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
          appId: String.fromEnvironment('FIREBASE_APP_ID'),
          messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
          projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
          iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
        ));
      }
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (generation != _generation || permission.authorizationStatus == AuthorizationStatus.denied) return;
      _ready = true;
      final token = await messaging.getToken();
      if (generation != _generation) return;
      if (token != null) await _register(token);
      if (generation != _generation) return;
      await _refresh?.cancel(); await _opened?.cancel(); await _foreground?.cancel();
      _refresh = messaging.onTokenRefresh.listen((token) async {
        try { await _register(token); } catch (_) { debugPrint('Không thể cập nhật đăng ký thông báo.'); }
      });
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (message.data['type'] == 'WEEKLY_REPORT') onOpen(message.data);
      });
      _foreground = FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] == 'WEEKLY_REPORT') onForeground();
      });
      final initial = await messaging.getInitialMessage();
      if (generation == _generation && initial?.data['type'] == 'WEEKLY_REPORT') onOpen(initial!.data);
    } catch (_) { debugPrint('Thông báo chưa sẵn sàng; báo cáo vẫn xem được trong ứng dụng.'); }
  }

  Future<void> _register(String token) async {
    final session = CaregiverApiService.instance;
    final jwt = await session.getToken();
    if (jwt == null) return;
    final response = await http.put(Uri.parse('${session.currentServerUrl}/api/v1/caregivers/push-token'),
      headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
      body: jsonEncode({'token': token})).timeout(const Duration(seconds: 5));
    if (response.statusCode != 204) throw StateError('Push registration failed');
  }

  Future<void> stop() async {
    _generation++;
    await _refresh?.cancel(); await _opened?.cancel(); await _foreground?.cancel();
    _refresh = null; _opened = null; _foreground = null;
  }

  Future<void> unregister() async {
    await stop();
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final session = CaregiverApiService.instance;
      final jwt = await session.getToken();
      if (token != null && jwt != null) {
        await http.delete(Uri.parse('${session.currentServerUrl}/api/v1/caregivers/push-token'),
          headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
          body: jsonEncode({'token': token})).timeout(const Duration(seconds: 5));
      }
    } catch (_) { debugPrint('Chưa thể thu hồi đăng ký thông báo trên máy chủ.'); }
    finally {
      try { await FirebaseMessaging.instance.deleteToken(); } catch (_) { }
      _ready = false;
    }
  }
}
