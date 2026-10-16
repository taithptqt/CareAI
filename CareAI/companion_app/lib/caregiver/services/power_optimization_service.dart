import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PowerOptimizationService {
  PowerOptimizationService._();
  static final instance = PowerOptimizationService._();

  static const _channel = MethodChannel('vn.careai.companion/power_optimization');
  static const _prefDismissed = 'caregiver_power_onboarding_dismissed';

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestIgnoreBatteryOptimizations() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAutostartSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final res = await _channel.invokeMethod<bool>('openAutostartSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> getManufacturer() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'Apple';
    }
    try {
      final res = await _channel.invokeMethod<String>('getManufacturer');
      return res ?? 'Android';
    } catch (_) {
      return 'Android';
    }
  }

  Future<bool> shouldShowOnboarding() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_prefDismissed) ?? false;
    if (dismissed) return false;

    final isIgnored = await isIgnoringBatteryOptimizations();
    return !isIgnored;
  }

  Future<void> dismissOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefDismissed, true);
  }
}
