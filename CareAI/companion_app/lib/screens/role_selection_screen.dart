import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../caregiver/services/caregiver_api_service.dart';
import '../caregiver/screens/home_screen.dart';
import '../caregiver/screens/login_screen.dart';
import 'device_pairing_screen.dart';
import 'sos_button_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  static const String prefSelectedRole = 'careai_selected_role';

  Future<void> _selectRole(BuildContext context, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefSelectedRole, role);

    if (!context.mounted) return;

    if (role == 'elder') {
      // Điều hướng luồng Người cao tuổi (Companion)
      final isPaired = await ApiService.instance.isPaired();
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => isPaired ? const SosButtonScreen() : const DevicePairingScreen(),
        ),
      );
    } else {
      // Điều hướng luồng Người thân (Caregiver)
      await CaregiverApiService.instance.init();
      final isLoggedIn = await CaregiverApiService.instance.isLoggedIn();
      if (!context.mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              // Logo & Tiêu đề
              Center(
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.25),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'CareAI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Hệ thống Y tế Từ xa & Cảnh báo Cấp cứu Gia đình',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 36),

              const Text(
                'VUI LÒNG CHỌN VAI TRÒ SỬ DỤNG:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF38BDF8),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 16),

              // Thẻ Vai trò 1: Người cao tuổi
              _RoleCard(
                icon: Icons.personal_injury_rounded,
                iconColor: const Color(0xFFEF4444),
                iconBgColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                title: 'Chế độ Người Cao Tuổi',
                subtitle: 'Thiết bị đồng hành (Companion)',
                description:
                    'Kích hoạt phím bấm SOS cứu nạn khẩn cấp, cảm biến ngã phần cứng, còi hú y tế ICU 1350Hz và kết nối đồng hồ Galaxy Watch.',
                badgeText: 'MẶC ĐỊNH CHO MÁY CỦA CỤ',
                badgeColor: const Color(0xFFDC2626),
                onTap: () => _selectRole(context, 'elder'),
              ),

              const SizedBox(height: 18),

              // Thẻ Vai trò 2: Người thân
              _RoleCard(
                icon: Icons.shield_rounded,
                iconColor: const Color(0xFF0284C7),
                iconBgColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
                borderColor: const Color(0xFF0284C7).withValues(alpha: 0.35),
                title: 'Chế độ Người Thân / Con Cháu',
                subtitle: 'Bảng điều khiển từ xa (Caregiver)',
                description:
                    'Theo dõi sinh hiệu thời gian thực, nhận còi báo động Quorum đa người thân, tiếp nhận cứu hộ (ACK) và quản lý nhóm gia đình.',
                badgeText: 'CHO CON CHÁU THEO DÕI',
                badgeColor: const Color(0xFF0284C7),
                onTap: () => _selectRole(context, 'caregiver'),
              ),

              const Spacer(),

              // Ghi chú dưới cùng
              const Center(
                child: Text(
                  '💡 Bạn có thể dễ dàng chuyển đổi vai trò bất kỳ lúc nào trong mục Cài đặt tài khoản.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final Color borderColor;
  final String title;
  final String subtitle;
  final String description;
  final String badgeText;
  final Color badgeColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.badgeText,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: iconColor.withValues(alpha: 0.15),
        highlightColor: iconColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: iconColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF64748B),
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
