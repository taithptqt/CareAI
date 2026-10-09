import 'package:careai_companion/caregiver/models/models.dart';
import 'package:careai_companion/caregiver/screens/incident_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('incident payload keeps vitals, location and alert cycle', () {
    final incident = Incident.fromJson({
      'id': 'incident-1', 'elderProfileId': 'elder-1', 'elderName': 'Cụ An',
      'triggeredByDeviceId': 'device-1', 'emergencyType': 'FALL',
      'severity': 'Critical', 'status': 'Open',
      'triggeredAt': '2026-09-25T08:00:00Z', 'timeline': [],
      'snapshot': {'heartRateBpm': 185, 'spO2Percent': 91,
        'gpsLocation': '10.5,106.7', 'currentGpsLocation': '10.6, 106.8',
        'currentGpsMeasuredAt': '2026-09-25T08:01:00Z',
        'currentGpsIsSimulated': true, 'currentGpsAccuracyMeters': 5,
        'homeAddress': '12 Đường A'},
      'alertState': {'cycleNumber': 2},
    });
    expect(incident.snapshot?.heartRateBpm, 185);
    expect(incident.snapshot?.gpsLocation, '10.5,106.7');
    expect(incident.snapshot?.currentGpsLocation, '10.6, 106.8');
    expect(incident.snapshot?.currentGpsIsSimulated, true);
    expect(incident.snapshot?.currentGpsAccuracyMeters, 5);
    expect(incident.snapshot?.homeAddress, '12 Đường A');
    expect(incident.alertState?.cycleNumber, 2);
  });

  testWidgets('emergency screen shows recorded vitals and disables missing contact', (tester) async {
    final incident = Incident.fromJson({
      'id': 'incident-2', 'elderProfileId': 'elder-2', 'elderName': 'Cụ Bình',
      'triggeredByDeviceId': 'device-2', 'emergencyType': 'MANUAL_SOS',
      'severity': 'Critical', 'status': 'Open',
      'triggeredAt': '2026-09-25T08:00:00Z', 'timeline': [],
      'snapshot': {'heartRateBpm': 185, 'spO2Percent': 92,
        'homeAddress': 'Số 8 Nguyễn Trãi'},
    });
    await tester.pumpWidget(MaterialApp(home: IncidentDetailScreen(incident: incident)));
    expect(find.text('185 bpm'), findsOneWidget);
    expect(find.text('Số 8 Nguyễn Trãi'), findsOneWidget);
    expect(find.text('Chưa có dữ liệu'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Chưa có số liên hệ của người cao tuổi'), 200,
        scrollable: find.byType(Scrollable).first);
    final callButton = tester.widget<FilledButton>(find.widgetWithText(
      FilledButton, 'Chưa có số liên hệ của người cao tuổi'));
    expect(callButton.onPressed, isNull);
    expect(find.text('Gọi cấp cứu 115'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
