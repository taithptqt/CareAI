import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:careai_companion/caregiver/screens/feedback_screen.dart';
import 'package:careai_companion/caregiver/services/feedback_api.dart';

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'jwt_token': 'fictional-test-token',
    }),
  );

  testWidgets('submits feedback and displays the admin reply from history', (
    tester,
  ) async {
    var submitted = false;
    final item = <String, dynamic>{
      'id': 'fictional-feedback',
      'category': 'Suggestion',
      'subject': 'Góp ý thử nghiệm',
      'message': 'Nội dung góp ý thử nghiệm không có dữ liệu thật.',
      'createdAtUtc': '2026-10-23T03:00:00Z',
      'status': 'Resolved',
      'adminReply': 'CareAI đã ghi nhận đề xuất thử nghiệm.',
      'repliedAtUtc': '2026-10-23T04:00:00Z',
    };
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer fictional-test-token');
      if (request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['requestId'], matches(RegExp(r'^[a-f0-9]{32}$')));
        expect(body['subject'], 'Góp ý thử nghiệm');
        submitted = true;
        return http.Response(
          jsonEncode(item),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({
          'items': submitted ? [item] : [],
          'totalCount': submitted ? 1 : 0,
          'page': 1,
          'pageSize': 25,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = FeedbackApi(client: client);
    await tester.pumpWidget(MaterialApp(home: FeedbackScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Góp ý thử nghiệm',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      item['message'] as String,
    );
    await tester.ensureVisible(find.text('Gửi phản hồi'));
    await tester.tap(find.text('Gửi phản hồi'));
    await tester.pumpAndSettle();
    expect(submitted, isTrue);
    await tester.ensureVisible(find.text('Góp ý thử nghiệm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Góp ý thử nghiệm'));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data == 'CareAI đã ghi nhận đề xuất thử nghiệm.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    api.dispose();
  });

  testWidgets(
    'retry preserves request ID and draft after an uncertain failure',
    (tester) async {
      final requestIds = <String>[];
      final client = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '{"items":[],"totalCount":0,"page":1,"pageSize":25}',
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requestIds.add(body['requestId'] as String);
        return http.Response('{}', 503);
      });
      final api = FeedbackApi(client: client);
      await tester.pumpWidget(MaterialApp(home: FeedbackScreen(api: api)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Góp ý gửi lại');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Nội dung thử lại khi kết nối chưa xác nhận.',
      );
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('Gửi phản hồi'));
        await tester.tap(find.text('Gửi phản hồi'));
        await tester.pumpAndSettle();
      }
      expect(requestIds, hasLength(2));
      expect(requestIds[0], requestIds[1]);
      expect(find.text('Góp ý gửi lại'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    },
  );
}
