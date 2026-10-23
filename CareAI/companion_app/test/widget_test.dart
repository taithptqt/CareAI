import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/main.dart';
import 'package:careai_companion/screens/device_pairing_screen.dart';

void main() {
  testWidgets('CareAiUnifiedApp smoke test loads DevicePairingScreen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const CareAiUnifiedApp(initialScreen: DevicePairingScreen()),
    );

    expect(find.text('Kết nối gia đình'), findsOneWidget);
    expect(find.text('Gần nhau hơn,\ntừ một kết nối.'), findsOneWidget);
    await tester.tap(find.text('Kết nối thiết bị'));
    await tester.pumpAndSettle();
    expect(find.text('Mã PIN phải gồm đúng 6 chữ số'), findsOneWidget);
  });
}
