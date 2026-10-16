import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/models/device_models.dart';
import 'package:careai_companion/services/fall_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Closed-Loop Incident Feedback Tests', () {
    test('DeviceActiveIncidentResponse parses ACKNOWLEDGED payload correctly', () {
      final json = {
        'hasActiveIncident': true,
        'incidentId': 'INC_TEST_888',
        'status': 'ACKNOWLEDGED',
        'emergencyType': 'MANUAL_SOS',
        'triggeredAt': '2026-10-16T06:00:00Z',
        'acknowledgedAt': '2026-10-16T06:02:30Z',
        'acknowledgedByName': 'Nguyễn Văn Con',
        'acknowledgedNote': 'Con đang chạy về đây, bố mẹ yên tâm!',
        'resolvedAt': null,
        'resolvedByName': null,
        'resolutionNotes': null,
      };

      final response = DeviceActiveIncidentResponse.fromJson(json);

      expect(response.hasActiveIncident, isTrue);
      expect(response.incidentId, equals('INC_TEST_888'));
      expect(response.status, equals('ACKNOWLEDGED'));
      expect(response.emergencyType, equals('MANUAL_SOS'));
      expect(response.acknowledgedByName, equals('Nguyễn Văn Con'));
      expect(response.acknowledgedNote, contains('yên tâm'));
      expect(response.acknowledgedAt, isNotNull);
      expect(response.resolvedAt, isNull);
    });

    test('DeviceActiveIncidentResponse parses RESOLVED payload correctly', () {
      final json = {
        'hasActiveIncident': false,
        'incidentId': 'INC_TEST_888',
        'status': 'RESOLVED',
        'emergencyType': 'FALL',
        'triggeredAt': '2026-10-16T06:00:00Z',
        'acknowledgedAt': '2026-10-16T06:02:30Z',
        'acknowledgedByName': 'Nguyễn Văn Con',
        'acknowledgedNote': 'Con đang về',
        'resolvedAt': '2026-10-16T06:15:00Z',
        'resolvedByName': 'Nguyễn Văn Con',
        'resolutionNotes': 'Cụ đã ổn định huyết áp, không chấn thương.',
      };

      final response = DeviceActiveIncidentResponse.fromJson(json);

      expect(response.hasActiveIncident, isFalse);
      expect(response.status, equals('RESOLVED'));
      expect(response.resolvedByName, equals('Nguyễn Văn Con'));
      expect(response.resolutionNotes, contains('huyết áp'));
    });

    test('DeviceActiveIncidentResponse parses NONE status when no incident exists', () {
      final json = {
        'hasActiveIncident': false,
        'incidentId': null,
        'status': 'NONE',
      };

      final response = DeviceActiveIncidentResponse.fromJson(json);

      expect(response.hasActiveIncident, isFalse);
      expect(response.status, equals('NONE'));
      expect(response.incidentId, isNull);
    });

    test('FallService.notifyIncidentStatusToWatch invokes fall_bridge with correct payload', () async {
      const channel = MethodChannel('vn.careai.companion/fall_bridge');
      MethodCall? capturedCall;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'notifyIncidentStatusToWatch') {
          capturedCall = call;
          return true;
        }
        return null;
      });

      final success = await FallService.instance.notifyIncidentStatusToWatch(
        status: 'ACKNOWLEDGED',
        acknowledgedByName: 'Trần Văn Con',
        notes: 'Đang đến',
        incidentId: 'INC_999',
      );

      expect(success, isTrue);
      expect(capturedCall, isNotNull);
      expect(capturedCall!.method, equals('notifyIncidentStatusToWatch'));
      final args = capturedCall!.arguments as Map;
      expect(args['status'], equals('ACKNOWLEDGED'));
      expect(args['acknowledgedByName'], equals('Trần Văn Con'));
      expect(args['notes'], equals('Đang đến'));
      expect(args['incidentId'], equals('INC_999'));
    });
  });
}
