import 'package:flutter_test/flutter_test.dart';
import 'package:caregiver_app/main.dart';

void main() {
  testWidgets('CaregiverApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const CaregiverApp(isLoggedIn: false));
    expect(find.byType(CaregiverApp), findsOneWidget);
  });
}
