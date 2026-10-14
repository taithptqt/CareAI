import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/caregiver/models/models.dart';

void main() {
  group('Gói A - Biểu đồ Sinh hiệu Chuyên sâu Models Tests', () {
    test('BloodPressureHistoryData deserializes correctly with WHO classification', () {
      final json = {
        'points': [
          {'timestamp': '2026-09-24T08:00:00Z', 'systolic': 120.0, 'diastolic': 80.0},
          {'timestamp': '2026-09-25T08:00:00Z', 'systolic': 135.0, 'diastolic': 85.0},
        ],
        'latestSystolic': 135.0,
        'latestDiastolic': 85.0,
        'classification': 'Tiền tăng huyết áp',
        'statusColor': 'YELLOW',
      };

      final data = BloodPressureHistoryData.fromJson(json);
      expect(data.points.length, 2);
      expect(data.points[0].systolic, 120.0);
      expect(data.points[0].diastolic, 80.0);
      expect(data.points[1].systolic, 135.0);
      expect(data.points[1].diastolic, 85.0);
      expect(data.latestSystolic, 135.0);
      expect(data.latestDiastolic, 85.0);
      expect(data.classification, 'Tiền tăng huyết áp');
      expect(data.statusColor, 'YELLOW');
    });

    test('Spo224hData deserializes correctly with min/max/avg and dips count', () {
      final json = {
        'points': [
          {'timestamp': '2026-09-25T02:00:00Z', 'value': 93.5},
          {'timestamp': '2026-09-25T04:00:00Z', 'value': 94.0},
          {'timestamp': '2026-09-25T08:00:00Z', 'value': 98.0},
        ],
        'minSpo2': 93.5,
        'maxSpo2': 98.0,
        'avgSpo2': 95.17,
        'latestSpo2': 98.0,
        'dipsBelow95Count': 2,
        'statusColor': 'YELLOW',
      };

      final data = Spo224hData.fromJson(json);
      expect(data.points.length, 3);
      expect(data.points[0].value, 93.5);
      expect(data.minSpo2, 93.5);
      expect(data.maxSpo2, 98.0);
      expect(data.avgSpo2, 95.17);
      expect(data.latestSpo2, 98.0);
      expect(data.dipsBelow95Count, 2);
      expect(data.statusColor, 'YELLOW');
    });

    test('HourlyStepsData deserializes 24h distribution and peak hour correctly', () {
      final json = {
        'hourlySteps': [
          {'hour': 6, 'steps': 450},
          {'hour': 7, 'steps': 820},
          {'hour': 8, 'steps': 350},
        ],
        'totalStepsToday': 1620,
        'peakHour': 7,
        'peakSteps': 820,
      };

      final data = HourlyStepsData.fromJson(json);
      expect(data.hourlySteps.length, 3);
      expect(data.hourlySteps[1].hour, 7);
      expect(data.hourlySteps[1].steps, 820);
      expect(data.totalStepsToday, 1620);
      expect(data.peakHour, 7);
      expect(data.peakSteps, 820);
    });

    test('ElderDashboard deserializes watchStatus and watchDisconnectReason correctly', () {
      final jsonBtOff = {
        'elderProfileId': 'ELDER_001',
        'fullName': 'Cụ Lê Thị Bình',
        'age': 81,
        'statusBadgeColor': 'GREEN',
        'deviceStatus': 'ONLINE',
        'todaySteps': 3200,
        'stepGoal': 6000,
        'watchModel': 'Galaxy Watch6',
        'watchStatus': 'DISCONNECTED',
        'watchDisconnectReason': 'BLUETOOTH_OFF',
      };

      final dashboardBtOff = ElderDashboard.fromJson(jsonBtOff);
      expect(dashboardBtOff.watchModel, 'Galaxy Watch6');
      expect(dashboardBtOff.watchStatus, 'DISCONNECTED');
      expect(dashboardBtOff.watchDisconnectReason, 'BLUETOOTH_OFF');

      final jsonSignalLost = {
        'elderProfileId': 'ELDER_002',
        'fullName': 'Cụ Trần Văn Nam',
        'age': 78,
        'statusBadgeColor': 'GREEN',
        'deviceStatus': 'ONLINE',
        'todaySteps': 1500,
        'stepGoal': 6000,
        'watchModel': 'Apple Watch Series 9',
        'watchStatus': 'DISCONNECTED',
        'watchDisconnectReason': 'SIGNAL_LOST',
      };

      final dashboardSignalLost = ElderDashboard.fromJson(jsonSignalLost);
      expect(dashboardSignalLost.watchModel, 'Apple Watch Series 9');
      expect(dashboardSignalLost.watchStatus, 'DISCONNECTED');
      expect(dashboardSignalLost.watchDisconnectReason, 'SIGNAL_LOST');
    });

    test('ElderDashboard deserializes isWatchWorn, isWatchCharging, and watchBatteryLevel correctly', () {
      final jsonWornCharging = {
        'elderProfileId': 'ELDER_003',
        'fullName': 'Cụ Phạm Gia Huy',
        'age': 82,
        'statusBadgeColor': 'GREEN',
        'deviceStatus': 'ONLINE',
        'todaySteps': 4100,
        'stepGoal': 6000,
        'watchModel': 'Galaxy Watch7',
        'watchStatus': 'ONLINE',
        'isWatchWorn': false,
        'isWatchCharging': true,
        'watchBatteryLevel': 100,
      };

      final dashboard = ElderDashboard.fromJson(jsonWornCharging);
      expect(dashboard.watchModel, 'Galaxy Watch7');
      expect(dashboard.watchStatus, 'ONLINE');
      expect(dashboard.isWatchWorn, isFalse);
      expect(dashboard.isWatchCharging, isTrue);
      expect(dashboard.watchBatteryLevel, 100);

      final jsonOnWrist = {
        'elderProfileId': 'ELDER_004',
        'fullName': 'Cụ Hoàng Kim Chi',
        'age': 79,
        'statusBadgeColor': 'GREEN',
        'deviceStatus': 'ONLINE',
        'todaySteps': 5200,
        'stepGoal': 6000,
        'watchModel': 'Apple Watch Series 10',
        'watchStatus': 'ONLINE',
        'isWatchWorn': true,
        'isWatchCharging': false,
        'watchBatteryLevel': 75,
      };

      final dashboardOnWrist = ElderDashboard.fromJson(jsonOnWrist);
      expect(dashboardOnWrist.watchModel, 'Apple Watch Series 10');
      expect(dashboardOnWrist.watchStatus, 'ONLINE');
      expect(dashboardOnWrist.isWatchWorn, isTrue);
      expect(dashboardOnWrist.isWatchCharging, isFalse);
      expect(dashboardOnWrist.watchBatteryLevel, 75);
    });
  });
}

