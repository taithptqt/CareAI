import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:careai_companion/caregiver/services/power_optimization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PowerOptimizationService Tests', () {
    const channel = MethodChannel('vn.careai.companion/power_optimization');
    final List<MethodCall> log = [];

    setUp(() {
      log.clear();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'isIgnoringBatteryOptimizations':
            return false;
          case 'requestIgnoreBatteryOptimizations':
            return true;
          case 'openAutostartSettings':
            return true;
          case 'getManufacturer':
            return 'Xiaomi';
          case 'areNotificationsEnabled':
            return false;
          case 'openNotificationSettings':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('dismissOnboarding records dismissal in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('caregiver_power_onboarding_dismissed'), isNull);

      await PowerOptimizationService.instance.dismissOnboarding();
      expect(prefs.getBool('caregiver_power_onboarding_dismissed'), isTrue);
    });

    test('areNotificationsEnabled queries native channel correctly', () async {
      final enabled = await PowerOptimizationService.instance.areNotificationsEnabled();
      expect(enabled, isFalse);
      expect(log.any((c) => c.method == 'areNotificationsEnabled'), isTrue);
    });

    test('openNotificationSettings invokes native channel', () async {
      final res = await PowerOptimizationService.instance.openNotificationSettings();
      expect(res, isTrue);
      expect(log.any((c) => c.method == 'openNotificationSettings'), isTrue);
    });

    test('checkCriticalPermissionsStatus detects missing notifications and battery opt', () async {
      final status = await PowerOptimizationService.instance.checkCriticalPermissionsStatus();
      expect(status.notificationsEnabled, isFalse);
      expect(status.hasMissingCriticalPermissions, isTrue);
      expect(status.primaryWarningMessage, contains('Thông báo bị tắt'));
    });
  });
}
