import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CriticalPermissionsStatus {
  final bool notificationsEnabled;
  final bool batteryOptimizationIgnored;
  final bool backgroundDataRestricted;
  final String manufacturer;

  const CriticalPermissionsStatus({
    required this.notificationsEnabled,
    required this.batteryOptimizationIgnored,
    this.backgroundDataRestricted = false,
    required this.manufacturer,
  });

  bool get hasMissingCriticalPermissions =>
      !notificationsEnabled || !batteryOptimizationIgnored || backgroundDataRestricted;

  int get missingPermissionsCount {
    int count = 0;
    if (!notificationsEnabled) count++;
    if (!batteryOptimizationIgnored) count++;
    if (backgroundDataRestricted) count++;
    return count;
  }

  bool get onlyBatteryOptimizationMissing =>
      !batteryOptimizationIgnored && notificationsEnabled && !backgroundDataRestricted;

  bool get onlyNotificationsMissing =>
      !notificationsEnabled && batteryOptimizationIgnored && !backgroundDataRestricted;

  String? get primaryWarningMessage {
    if (!notificationsEnabled) {
      return 'Thông báo bị tắt! Còi hú cấp cứu không thể kêu khi người thân gặp nạn.';
    }
    if (!batteryOptimizationIgnored) {
      return 'Chạy ngầm bị hạn chế! Điện thoại có thể không nhận được cảnh báo khi tắt màn hình.';
    }
    if (backgroundDataRestricted) {
      return 'Dữ liệu nền bị Tiết kiệm pin/dữ liệu chặn! Cần cấp quyền để nhận cảnh báo ngầm.';
    }
    return null;
  }
}

class PowerOptimizationService {
  PowerOptimizationService._();
  static final instance = PowerOptimizationService._();

  static const _channel = MethodChannel('vn.careai.companion/power_optimization');
  static const _prefDismissed = 'caregiver_power_onboarding_dismissed';

  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> canRequestDirectNotificationPermission() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('canRequestDirectNotificationPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    if (kIsWeb) return true;
    try {
      final res = await _channel.invokeMethod<bool>('openNotificationSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

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

  Future<bool> isBackgroundDataRestricted() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isBackgroundDataRestricted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openBackgroundDataSettings() async {
    if (kIsWeb) return false;
    try {
      final res = await _channel.invokeMethod<bool>('openBackgroundDataSettings');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<CriticalPermissionsStatus> checkCriticalPermissionsStatus() async {
    final notifs = await areNotificationsEnabled();
    final battery = await isIgnoringBatteryOptimizations();
    final bgData = await isBackgroundDataRestricted();
    final mfg = await getManufacturer();
    return CriticalPermissionsStatus(
      notificationsEnabled: notifs,
      batteryOptimizationIgnored: battery,
      backgroundDataRestricted: bgData,
      manufacturer: mfg,
    );
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

  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDismissed) == null;
  }

  Future<bool> hasUserDismissedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefDismissed) ?? false;
  }
}
