import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../caregiver/screens/home_screen.dart';
import '../caregiver/screens/login_screen.dart';
import '../caregiver/services/caregiver_api_service.dart';
import '../services/api_service.dart';
import 'device_pairing_screen.dart';
import 'sos_button_screen.dart';
import '../theme/careai_theme.dart';
import '../widgets/careai_ui.dart';

/// Màn hình chọn vai trò sử dụng ban đầu (Role Selection Screen).
/// Giao diện nền trắng đồng bộ, thiết kế y tế hiện đại với Slogan trang trọng.
class RoleSelectionScreen extends StatelessWidget {
  static const String prefSelectedRole = 'careai_selected_role';

  const RoleSelectionScreen({super.key});

  Future<void> _selectRole(BuildContext context, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedRole, role);

    if (!context.mounted) return;

    if (role == 'elder') {
      final isPaired = await ApiService.instance.isPaired();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              isPaired ? const SosButtonScreen() : const DevicePairingScreen(),
        ),
      );
    } else if (role == 'caregiver') {
      final currentElderId = await ApiService.instance.getElderProfileId();
      final canEnterHomeScreen = await CaregiverApiService.instance
          .verifyOrLogoutIfMismatchedElder(currentElderId);

      if (!context.mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              canEnterHomeScreen ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: CareAiColors.canvas,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                children: [
                  const CareAiBrand(),
                  const SizedBox(height: 32),
                  Text(
                    'Một kết nối,\ntriệu yêu thương.',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Gần bên người thương, dù ở bất cứ đâu.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: CareAiColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      'assets/images/facare/welcome-family-hero.png',
                      height: 240,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      cacheWidth: 900,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const CareAiSectionHeading('Bạn sử dụng CareAI cho ai?'),
                  const SizedBox(height: 16),
                  _RoleChoice(
                    title: 'Dành cho người cao tuổi',
                    description: 'Báo cần giúp và kết nối với người thân.',
                    icon: Icons.elderly_rounded,
                    color: CareAiColors.greenSurface,
                    onTap: () => _selectRole(context, 'elder'),
                  ),
                  const SizedBox(height: 12),
                  _RoleChoice(
                    title: 'Dành cho người thân',
                    description: 'Theo dõi, nhận cảnh báo và cùng chăm sóc.',
                    icon: Icons.family_restroom_rounded,
                    color: CareAiColors.peach,
                    onTap: () => _selectRole(context, 'caregiver'),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Bạn có thể đổi vai trò trong phần cài đặt.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: CareAiColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(24),
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: CareAiColors.brown, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: CareAiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: CareAiColors.brown,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 22,
              color: CareAiColors.brown,
            ),
          ],
        ),
      ),
    ),
  );
}
