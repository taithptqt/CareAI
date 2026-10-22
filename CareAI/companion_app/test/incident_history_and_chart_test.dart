import 'package:careai_companion/caregiver/models/models.dart';
import 'package:careai_companion/caregiver/screens/incident_detail_screen.dart';
import 'package:careai_companion/caregiver/screens/incident_history_screen.dart';
import 'package:careai_companion/caregiver/widgets/heart_rate_chart_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HeartRateChartWidget Tests', () {
    testWidgets(
      'renders cardiac trend with statistics and marker when samples exist',
      (tester) async {
        final incidentTime = DateTime.parse('2026-09-25T08:00:00Z');
        final window = IncidentHeartRateWindow(
          incidentTriggeredAt: incidentTime,
          windowStart: incidentTime.subtract(const Duration(minutes: 15)),
          windowEnd: incidentTime.add(const Duration(minutes: 15)),
          samples: [
            HeartRateSample(
              bpm: 75,
              timestamp: incidentTime.subtract(const Duration(minutes: 10)),
            ),
            HeartRateSample(bpm: 185, timestamp: incidentTime),
            HeartRateSample(
              bpm: 90,
              timestamp: incidentTime.add(const Duration(minutes: 5)),
            ),
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HeartRateChartWidget(
                window: window,
                incidentTriggeredAt: incidentTime,
                snapshotHeartRate: 185,
              ),
            ),
          ),
        );

        expect(
          find.text('Biểu Đồ Nhịp Tim (T - 15 đến T + 15 phút)'),
          findsOneWidget,
        );
        expect(find.text('3 mẫu'), findsOneWidget);
        expect(find.text('Thấp nhất'), findsOneWidget);
        expect(find.text('75 bpm'), findsOneWidget);
        expect(find.text('Cao nhất'), findsOneWidget);
        expect(find.text('185 bpm'), findsOneWidget);
        expect(find.text('Mốc sự cố (T)'), findsOneWidget);
      },
    );

    testWidgets(
      'renders empty state message when no cardiac samples in window',
      (tester) async {
        final incidentTime = DateTime.parse('2026-09-25T08:00:00Z');
        final emptyWindow = IncidentHeartRateWindow(
          incidentTriggeredAt: incidentTime,
          windowStart: incidentTime.subtract(const Duration(minutes: 15)),
          windowEnd: incidentTime.add(const Duration(minutes: 15)),
          samples: [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HeartRateChartWidget(
                window: emptyWindow,
                incidentTriggeredAt: incidentTime,
                snapshotHeartRate: 182,
              ),
            ),
          ),
        );

        expect(find.text('Chưa Có Chuỗi Nhịp Tim ±15 Phút'), findsOneWidget);
        expect(
          find.textContaining('Không có mẫu đo nhịp tim nào được ghi nhận'),
          findsOneWidget,
        );
        expect(
          find.text('Nhịp tim tức thời tại mốc T: 182 bpm'),
          findsOneWidget,
        );
      },
    );
  });

  group('IncidentDetailScreen & Timeline Tests', () {
    testWidgets(
      'displays ACK info, Resolve notes, and chronological timeline',
      (tester) async {
        final incident = Incident.fromJson({
          'id': 'inc-resolved-101',
          'elderProfileId': 'elder-1',
          'elderName': 'Cụ Trần Văn Nam',
          'triggeredByDeviceId': 'watch-1',
          'emergencyType': 'CRITICAL_HIGH_HR',
          'severity': 'Critical',
          'status': 'Resolved',
          'triggeredAt': '2026-09-25T08:00:00Z',
          'acknowledgedAt': '2026-09-25T08:00:45Z',
          'acknowledgedByCaregiverId': 'caregiver-01',
          'resolvedAt': '2026-09-25T08:15:30Z',
          'resolvedByCaregiverId': 'caregiver-01',
          'resolutionNotes':
              'Cụ đã ngồi nghỉ, uống nước, nhịp tim đo lại 78 bpm ổn định.',
          'snapshot': {
            'heartRateBpm': 188,
            'spO2Percent': 95,
            'bpSystolic': 130,
            'bpDiastolic': 85,
            'homeAddress': '123 Phố Huế, Hà Nội',
          },
          'timeline': [
            {
              'eventType': 'CREATED',
              'description': 'Hệ thống AI phát hiện nhịp tim nguy kịch 188 bpm',
              'recordedAt': '2026-09-25T08:00:00Z',
            },
            {
              'eventType': 'ACKNOWLEDGED',
              'description': 'Người thân đã tiếp nhận sự cố',
              'recordedAt': '2026-09-25T08:00:45Z',
            },
            {
              'eventType': 'RESOLVED',
              'description': 'Sự cố đã được giải quyết an toàn',
              'recordedAt': '2026-09-25T08:15:30Z',
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(home: IncidentDetailScreen(incident: incident)),
        );

        // Kiểm tra tiêu đề và trạng thái
        expect(find.text('Chi tiết sự cố đã đóng'), findsOneWidget);
        expect(find.text('Cụ Trần Văn Nam'), findsOneWidget);

        // Kiểm tra thẻ Tiếp Nhận (ACK)
        expect(find.text('Thông tin tiếp nhận'), findsOneWidget);

        // Kiểm tra thẻ Đóng Sự Cố (Resolved) và Ghi chú lâm sàng
        expect(find.text('Thông tin giải quyết'), findsOneWidget);
        expect(
          find.text(
            'Cụ đã ngồi nghỉ, uống nước, nhịp tim đo lại 78 bpm ổn định.',
          ),
          findsOneWidget,
        );

        // Kiểm tra Dòng thời gian sự kiện
        await tester.scrollUntilVisible(
          find.text('Dòng thời gian sự kiện'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Dòng thời gian sự kiện'), findsOneWidget);
        expect(
          find.text('Hệ thống AI phát hiện nhịp tim nguy kịch 188 bpm'),
          findsOneWidget,
        );
        expect(find.text('Người thân đã tiếp nhận sự cố'), findsOneWidget);
        expect(find.text('Sự cố đã được giải quyết an toàn'), findsOneWidget);
      },
    );

    testWidgets(
      'displays re-escalation banner when incident re-opened after ACK',
      (tester) async {
        final incident = Incident.fromJson({
          'id': 'inc-reescalated-102',
          'elderProfileId': 'elder-2',
          'elderName': 'Cụ Lê Thị Mai',
          'triggeredByDeviceId': 'watch-2',
          'emergencyType': 'CRITICAL_HIGH_HR',
          'severity': 'Critical',
          'status': 'Open',
          'triggeredAt': '2026-09-25T08:00:00Z',
          'acknowledgedAt': '2026-09-25T08:01:00Z',
          'alertState': {'cycleNumber': 2},
          'timeline': [
            {
              'eventType': 'CREATED',
              'description': 'Kích hoạt sự cố',
              'recordedAt': '2026-09-25T08:00:00Z',
            },
            {
              'eventType': 'ACKNOWLEDGED',
              'description': 'Đã tiếp nhận chu kỳ 1',
              'recordedAt': '2026-09-25T08:01:00Z',
            },
            {
              'eventType': 'RE_ESCALATED',
              'description': 'Nhịp tim nguy kịch mới sau ACK. Tái mở chu kỳ 2.',
              'recordedAt': '2026-09-25T08:05:00Z',
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(home: IncidentDetailScreen(incident: incident)),
        );

        expect(
          find.text('Cảnh Báo Tái Mở / Nhắc Lại (Chu kỳ 2)'),
          findsOneWidget,
        );
        expect(find.text('Cần người thân tiếp nhận ngay.'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Nhịp tim nguy kịch mới sau ACK. Tái mở chu kỳ 2.'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Nhịp tim nguy kịch mới sau ACK. Tái mở chu kỳ 2.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'resolves technical signal loss incident in 1 tap without showing AlertDialog',
      (tester) async {
        final incident = Incident.fromJson({
          'id': 'inc-stale-201',
          'elderProfileId': 'elder-stale',
          'elderName': 'Cụ Đỗ Văn Khang',
          'triggeredByDeviceId': 'watch-stale',
          'emergencyType': 'STALE_OFFLINE',
          'severity': 'Medium',
          'status': 'Acknowledged',
          'triggeredAt': '2026-10-17T08:00:00Z',
          'acknowledgedAt': '2026-10-17T08:05:00Z',
          'acknowledgedByCaregiverId': 'caregiver-01',
          'timeline': [
            {
              'eventType': 'TRIGGERED',
              'description': 'Mất tín hiệu thiết bị',
              'recordedAt': '2026-10-17T08:00:00Z',
            },
            {
              'eventType': 'ACKNOWLEDGED',
              'description': 'Người thân tiếp nhận',
              'recordedAt': '2026-10-17T08:05:00Z',
            },
          ],
        });

        await tester.pumpWidget(
          MaterialApp(home: IncidentDetailScreen(incident: incident)),
        );

        expect(find.text('Giải quyết sự cố'), findsOneWidget);

        await tester.tap(find.text('Giải quyết sự cố'));
        await tester.pump();

        // Kiểm tra KHÔNG xuất hiện AlertDialog (1-Tap resolve)
        expect(find.byType(AlertDialog), findsNothing);
      },
    );
  });

  group('IncidentHistoryScreen UI & Filters Tests', () {
    testWidgets('renders filter chips and empty state properly', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: IncidentHistoryScreen(
            initialElderProfileId: 'elder-demo',
            initialElderName: 'Cụ Nguyễn Văn Demo',
          ),
        ),
      );

      // Kiểm tra thanh tiêu đề
      expect(find.text('Lịch sử chăm sóc'), findsOneWidget);

      // Kiểm tra các chip bộ lọc
      expect(find.text('Tất cả trạng thái'), findsOneWidget);
      expect(find.text('Đang mở'), findsOneWidget);
      expect(find.text('Đã tiếp nhận'), findsOneWidget);
      expect(find.text('Đã giải quyết'), findsOneWidget);

      expect(find.text('Tất cả loại'), findsOneWidget);
      expect(find.text('Té Ngã'), findsOneWidget);
      expect(find.text('Nút SOS'), findsOneWidget);
      expect(find.text('Nhịp tim ≥180'), findsOneWidget);
      expect(find.text('Nhịp tim ≤35'), findsOneWidget);
    });
  });
}
