import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Màn hình khởi động chính thức của dự án CareAI (Splash Screen).
/// Hiển thị nền sóng ngọc bích mở rộng toàn màn hình, logo hòa quyện không khung viền,
/// và duy nhất Tên ứng dụng "CareAI" kèm Slogan "Chăm sóc từ xa, yêu thương gần hơn" đặt ngay trên logo.
class SplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const SplashScreen({super.key, required this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutBack,
      ),
    );

    _animController.forward();

    // Giữ màn hình khởi động 2.2 giây để hiển thị trọn vẹn thông điệp thương hiệu
    Timer(const Duration(milliseconds: 2200), _navigateToNextScreen);
  }

  void _navigateToNextScreen() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, animation, secondaryAnimation) => widget.nextScreen,
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Phóng to logo sát viền nhưng tuyệt đối không chạm viền (~72% chiều rộng màn hình)
    final logoSize = (screenWidth * 0.72).clamp(260.0, 320.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Hiệu ứng nền sóng uốn lượn mở rộng ra toàn màn hình khởi động
            Positioned.fill(
              child: Image.asset(
                'assets/images/splash_wave_bg.png',
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),

            // 2. Nội dung chính: Slogan đặt NGAY TRÊN Logo và Logo phóng to hòa quyện ở giữa
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // TÊN APP - CHỮ NGHIÊNG, UỐN LƯỢN NGHỆ THUẬT VỚI DẢI MÀU GRADIENT NGỌC BÍCH
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: const Padding(
                              padding: EdgeInsets.only(right: 14.0, top: 4.0, bottom: 4.0, left: 4.0),
                              child: Text(
                                'CareAI',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 46,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white, // Dùng màu trắng để dải gradient hiển thị rực rỡ
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // DÒNG SLOGAN NGHỆ THUẬT: Chăm sóc từ xa, yêu thương gần hơn - NÉT THANH ĐẬM UỐN LƯỢN THANH THOÁT
                          Image.asset(
                            'assets/images/slogan_banner.png',
                            width: (screenWidth * 0.88).clamp(280.0, 360.0),
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 28),

                          // LOGO Ở GIỮA PHÓNG TO, HÒA QUYỆN VỚI NỀN SÓNG (KHÔNG NỀN TRẮNG, KHÔNG KHUNG TRÒN, KHÔNG GẠCH NGANG)
                          Image.asset(
                            'assets/images/logo.png',
                            width: logoSize,
                            height: logoSize,
                            fit: BoxFit.contain,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
