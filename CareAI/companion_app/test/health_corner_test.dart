import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/caregiver/screens/health_corner_screen.dart';
import 'package:careai_companion/caregiver/services/health_report_api.dart';

class FakeHealthApi implements HealthReportApi {
  bool fail = false;
  bool empty = false;
  final List<int?> cursors = [];
  @override
  Future<Map<String, dynamic>> get(String elderId, String resource, {int? beforeId}) async {
    if (fail) throw Exception('Mất kết nối');
    if (resource.startsWith('weekly-reports/')) {
      return {'weekStartUtc': '2026-09-13T00:00:00Z', 'content': '1. Tổng quan sức khỏe tuần\nBáo cáo kiểm thử'};
    }
    if (empty) return {'items': [], 'nextBeforeId': null};
    if (resource == 'insights') {
      return {
        'items': [{'id': 1, 'insightType': 'NIGHT_HEART_RATE_SPIKE', 'windowEndUtc': '2026-09-20T06:00:00Z', 'observedValue': 100, 'baselineValue': 65}],
        'nextBeforeId': null,
      };
    }
    cursors.add(beforeId);
    return {
      'items': [{'id': beforeId == null ? 2 : 1, 'weekStartUtc': beforeId == null ? '2026-09-13T00:00:00Z' : '2026-09-06T00:00:00Z',
        'weekEndUtc': '2026-09-20T00:00:00Z', 'source': 'RULE_BASED'}],
      'nextBeforeId': beforeId == null ? 2 : null,
    };
  }
}

void main() {
  testWidgets('Displays insights, report history and detail', (tester) async {
    final api = FakeHealthApi();
    await tester.pumpWidget(MaterialApp(home: HealthCornerScreen(elderId: 'elder', api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Nhịp tim ban đêm tăng'), findsOneWidget);
    await tester.tap(find.text('Báo cáo tuần'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tuần từ 13/09/2026'), findsOneWidget);
    await tester.tap(find.text('Xem các tuần trước / nhận định cũ'));
    await tester.pumpAndSettle();
    expect(api.cursors, [null, 2]);
    expect(find.textContaining('Tuần từ 06/09/2026'), findsOneWidget);
    await tester.tap(find.textContaining('Tuần từ 13/09/2026'));
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo sức khỏe tuần'), findsOneWidget);
    expect(find.textContaining('Báo cáo kiểm thử'), findsOneWidget);
  });

  testWidgets('Shows empty state without claiming health is normal', (tester) async {
    await tester.pumpWidget(MaterialApp(home: HealthCornerScreen(elderId: 'elder', api: FakeHealthApi()..empty = true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hệ thống cần đủ dữ liệu'), findsOneWidget);
  });

  testWidgets('Network failure can be retried', (tester) async {
    final api = FakeHealthApi()..fail = true;
    await tester.pumpWidget(MaterialApp(home: HealthCornerScreen(elderId: 'elder', api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Nhịp tim ban đêm tăng'), findsOneWidget);
  });
}
