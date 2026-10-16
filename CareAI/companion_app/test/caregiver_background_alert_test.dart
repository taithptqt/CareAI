import 'package:careai_companion/caregiver/services/caregiver_push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fall push starts native background alarm with incident and cycle', () async {
    final broadcasts = <Map<String, dynamic>>[];
    await dispatchNativeCaregiverAlert(const RemoteMessage(data: {
      'incidentId': 'fall-42',
      'alertCycleNumber': '3',
      'emergencyType': 'FALL',
      'siren': 'true',
      'title': 'Báo ngã khẩn cấp',
      'body': 'Cha mẹ cần trợ giúp',
    }), sendNative: (arguments) async => broadcasts.add(arguments));

    expect(broadcasts, hasLength(1));
    final args = broadcasts.single;
    expect(args['incidentId'], 'fall-42');
    expect(args['alertCycleNumber'], 3);
    expect(args['emergencyType'], 'FALL');
    expect(args['siren'], isTrue);
  });

  test('ACK push stops native alarm while app is in background', () async {
    final broadcasts = <Map<String, dynamic>>[];
    await dispatchNativeCaregiverAlert(const RemoteMessage(data: {
      'incidentId': 'fall-42',
      'alertCycleNumber': '3',
      'eventType': 'ACKNOWLEDGED',
      'siren': 'false',
    }), sendNative: (arguments) async => broadcasts.add(arguments));
    expect(broadcasts, hasLength(1));
    final args = broadcasts.single;
    expect(args['incidentId'], 'fall-42');
    expect(args['eventType'], 'ACKNOWLEDGED');
    expect(args['siren'], isFalse);
  });

  test('fallback polling direct alert formats emergency payload with high priority and siren', () async {
    final payload = <String, dynamic>{
      'incidentId': 'fall-99',
      'alertCycleNumber': 1,
      'eventType': 'FALL',
      'title': 'CẢNH BÁO CẤP CỨU',
      'body': 'Người cao tuổi cần trợ giúp ngay (FALL).',
      'emergencyType': 'FALL',
      'priority': 'CRITICAL',
      'siren': true,
    };
    expect(payload['incidentId'], 'fall-99');
    expect(payload['emergencyType'], 'FALL');
    expect(payload['priority'], 'CRITICAL');
    expect(payload['siren'], isTrue);
  });
}
