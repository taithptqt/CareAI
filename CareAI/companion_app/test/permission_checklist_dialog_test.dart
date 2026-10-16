import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:careai_companion/caregiver/services/power_optimization_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CriticalPermissionsStatus Rule & Logic Tests', () {
    test('onlyBatteryOptimizationMissing correctly identifies sole missing battery optimization', () {
      const status = CriticalPermissionsStatus(
        notificationsEnabled: true,
        batteryOptimizationIgnored: false,
        backgroundDataRestricted: false,
        manufacturer: 'Samsung',
      );
      expect(status.hasMissingCriticalPermissions, isTrue);
      expect(status.onlyBatteryOptimizationMissing, isTrue);
      expect(status.onlyNotificationsMissing, isFalse);
      expect(status.missingPermissionsCount, equals(1));
    });

    test('onlyNotificationsMissing correctly identifies sole missing notification', () {
      const status = CriticalPermissionsStatus(
        notificationsEnabled: false,
        batteryOptimizationIgnored: true,
        backgroundDataRestricted: false,
        manufacturer: 'Xiaomi',
      );
      expect(status.hasMissingCriticalPermissions, isTrue);
      expect(status.onlyNotificationsMissing, isTrue);
      expect(status.onlyBatteryOptimizationMissing, isFalse);
      expect(status.missingPermissionsCount, equals(1));
    });

    test('multiple missing permissions detected accurately', () {
      const status = CriticalPermissionsStatus(
        notificationsEnabled: false,
        batteryOptimizationIgnored: false,
        backgroundDataRestricted: true,
        manufacturer: 'Xiaomi',
      );
      expect(status.hasMissingCriticalPermissions, isTrue);
      expect(status.onlyNotificationsMissing, isFalse);
      expect(status.onlyBatteryOptimizationMissing, isFalse);
      expect(status.missingPermissionsCount, equals(3));
    });

    test('all permissions granted leaves hasMissingCriticalPermissions false', () {
      const status = CriticalPermissionsStatus(
        notificationsEnabled: true,
        batteryOptimizationIgnored: true,
        backgroundDataRestricted: false,
        manufacturer: 'Samsung',
      );
      expect(status.hasMissingCriticalPermissions, isFalse);
      expect(status.missingPermissionsCount, equals(0));
      expect(status.primaryWarningMessage, isNull);
    });
  });
}
