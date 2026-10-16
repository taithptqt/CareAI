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
          case 'canRequestDirectNotificationPermission':
            return true;
          case 'requestNotificationPermission':
            return true;
          case 'openNotificationSettings':
            return true;
          case 'isBackgroundDataRestricted':
            return true;
          case 'openBackgroundDataSettings':
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

    test('canRequestDirectNotificationPermission and requestNotificationPermission invoke native channel', () async {
      final canDirect = await PowerOptimizationService.instance.canRequestDirectNotificationPermission();
      expect(canDirect, isTrue);
      expect(log.any((c) => c.method == 'canRequestDirectNotificationPermission'), isTrue);

      final requested = await PowerOptimizationService.instance.requestNotificationPermission();
      expect(requested, isTrue);
      expect(log.any((c) => c.method == 'requestNotificationPermission'), isTrue);
    });

    test('isFirstLaunch returns true before dismissal and false after', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await PowerOptimizationService.instance.isFirstLaunch(), isTrue);
      expect(await PowerOptimizationService.instance.hasUserDismissedOnboarding(), isFalse);

      await PowerOptimizationService.instance.dismissOnboarding();
      expect(await PowerOptimizationService.instance.isFirstLaunch(), isFalse);
      expect(await PowerOptimizationService.instance.hasUserDismissedOnboarding(), isTrue);
    });

    test('openNotificationSettings invokes native channel', () async {
      final res = await PowerOptimizationService.instance.openNotificationSettings();
      expect(res, isTrue);
      expect(log.any((c) => c.method == 'openNotificationSettings'), isTrue);
    });

    test('isBackgroundDataRestricted and openBackgroundDataSettings invoke native channel', () async {
      final isRestricted = await PowerOptimizationService.instance.isBackgroundDataRestricted();
      expect(isRestricted, isTrue);
      expect(log.any((c) => c.method == 'isBackgroundDataRestricted'), isTrue);

      final opened = await PowerOptimizationService.instance.openBackgroundDataSettings();
      expect(opened, isTrue);
      expect(log.any((c) => c.method == 'openBackgroundDataSettings'), isTrue);
    });

    test('checkCriticalPermissionsStatus detects missing notifications, battery opt, and background data', () async {
      final status = await PowerOptimizationService.instance.checkCriticalPermissionsStatus();
      expect(status.notificationsEnabled, isFalse);
      expect(status.backgroundDataRestricted, isTrue);
      expect(status.hasMissingCriticalPermissions, isTrue);
      expect(status.primaryWarningMessage, contains('Thông báo bị tắt'));

      const dataOnlyStatus = CriticalPermissionsStatus(
        notificationsEnabled: true,
        batteryOptimizationIgnored: true,
        backgroundDataRestricted: true,
        manufacturer: 'Samsung',
      );
      expect(dataOnlyStatus.hasMissingCriticalPermissions, isTrue);
      expect(dataOnlyStatus.primaryWarningMessage, contains('Dữ liệu nền bị Tiết kiệm pin/dữ liệu chặn'));
    });
  });
}
