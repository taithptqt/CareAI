import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../caregiver/screens/home_screen.dart';
import '../caregiver/screens/login_screen.dart';
import '../caregiver/services/caregiver_api_service.dart';
import '../services/api_service.dart';
import 'device_pairing_screen.dart';
import 'sos_button_screen.dart';

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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isPaired ? const SosButtonScreen() : const DevicePairingScreen(),
        ),
      );
    } else if (role == 'caregiver') {
      final currentElderId = await ApiService.instance.getElderProfileId();
      final canEnterHomeScreen = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder(currentElderId);

      if (!context.mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => canEnterHomeScreen ? const HomeScreen() : const LoginScreen(),
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
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                // Logo & Slogan Header
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 86,
                        height: 86,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'CareAI',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'HỆ THỐNG Y TẾ TỪ XA & CẢNH BÁO CẤP CỨU GIA ĐÌNH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                    letterSpacing: 0.6,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            const Color(0xFF0EA5E9).withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Đồng Hành Chăm Sóc • Cảnh Báo Tức Thì',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0284C7),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 1.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0EA5E9).withValues(alpha: 0.6),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                const Text(
                  'VUI LÒNG CHỌN VAI TRÒ SỬ DỤNG:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0284C7),
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 14),

                // Thẻ Vai trò 1: Người cao tuổi
                _RoleCard(
                  icon: Icons.personal_injury_rounded,
                  iconColor: const Color(0xFFDC2626),
                  iconBgColor: const Color(0xFFFEE2E2),
                  borderColor: const Color(0xFFFECACA),
                  title: 'Chế độ Người Cao Tuổi',
                  subtitle: 'Thiết bị đồng hành (Companion)',
                  description:
                      'Kích hoạt phím bấm SOS cứu nạn khẩn cấp, cảm biến ngã phần cứng, còi hú y tế ICU 1350Hz và kết nối đồng hồ Galaxy Watch.',
                  badgeText: 'MẶC ĐỊNH CHO MÁY NGƯỜI CAO TUỔI',
                  badgeColor: const Color(0xFFDC2626),
                  badgeBgColor: const Color(0xFFFEE2E2),
                  onTap: () => _selectRole(context, 'elder'),
                ),

                const SizedBox(height: 16),

                // Thẻ Vai trò 2: Người thân
                _RoleCard(
                  icon: Icons.shield_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBgColor: const Color(0xFFE0F2FE),
                  borderColor: const Color(0xFFBAE6FD),
                  title: 'Chế độ Người Thân / Con Cháu',
                  subtitle: 'Bảng điều khiển từ xa (Caregiver)',
                  description:
                      'Theo dõi sinh hiệu thời gian thực, nhận còi báo động Quorum đa người thân, tiếp nhận cứu hộ (ACK) và quản lý nhóm gia đình.',
                  badgeText: 'CHO CON CHÁU THEO DÕI',
                  badgeColor: const Color(0xFF0284C7),
                  badgeBgColor: const Color(0xFFE0F2FE),
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
                const SizedBox(height: 10),
              ],
            ),
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
  final Color badgeBgColor;
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
    required this.badgeBgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: iconColor.withValues(alpha: 0.12),
          highlightColor: iconColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: iconColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF94A3B8),
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBgColor,
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
      ),
    );
  }
}
