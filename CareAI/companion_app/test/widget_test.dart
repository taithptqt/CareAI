import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/main.dart';
import 'package:careai_companion/screens/device_pairing_screen.dart';

void main() {
  testWidgets('CareAiUnifiedApp smoke test loads DevicePairingScreen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const CareAiUnifiedApp(initialScreen: DevicePairingScreen()),
    );

    // Verify key titles on pairing screen
    expect(find.text('Ghép Nối Thiết Bị CareAI'), findsOneWidget);
    expect(find.text('Kích Hoạt Thiết Bị Giám Sát'), findsOneWidget);
  });
}
