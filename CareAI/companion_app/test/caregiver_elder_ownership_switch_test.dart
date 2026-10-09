import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:careai_companion/caregiver/services/caregiver_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Caregiver & Elder Ownership Verification Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'jwt_token': 'fake_jwt_token_123',
        'caregiver_id': 'CAREGIVER_001',
        'caregiver_name': 'Nguyen Van Caregiver',
        'caregiver_email': 'caregiver@example.com',
      });
      await CaregiverApiService.instance.init();
    });

    test('verifyOrLogoutIfMismatchedElder returns true when no elder is paired on device', () async {
      final canEnter = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder(null);
      expect(canEnter, isTrue);
      expect(await CaregiverApiService.instance.isLoggedIn(), isTrue);
    });

    test('verifyOrLogoutIfMismatchedElder returns true when elder is owned in cache', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('caregiver_cached_elder_ids', ['ELDER_001', 'ELDER_002']);

      // Khi offline / không gọi được API getMyElders
      final canEnter = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder('ELDER_001');
      expect(canEnter, isTrue);
      expect(await CaregiverApiService.instance.isLoggedIn(), isTrue);
    });

    test('verifyOrLogoutIfMismatchedElder logs out when elder does NOT belong to caregiver', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('caregiver_cached_elder_ids', ['ELDER_001', 'ELDER_002']);

      // Thiết bị đang gắn với ELDER_999 (thuộc tài khoản khác)
      final canEnter = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder('ELDER_999');
      expect(canEnter, isFalse);

      // Session cũ đã bị đăng xuất sạch sẽ
      expect(await CaregiverApiService.instance.isLoggedIn(), isFalse);
      expect(await CaregiverApiService.instance.getToken(), isNull);
      expect(prefs.getStringList('caregiver_cached_elder_ids'), isNull);
    });
  });
}
