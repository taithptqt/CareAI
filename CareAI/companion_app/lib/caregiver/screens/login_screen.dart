import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../screens/role_selection_screen.dart';
import '../services/caregiver_api_service.dart';
import 'home_screen.dart';
import 'server_config_dialog.dart';
import '../../theme/careai_theme.dart';
import '../../widgets/careai_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Controllers
  final _emailController = TextEditingController(text: 'con@careai.vn');
  final _passwordController = TextEditingController(text: 'CareAi123456');
  final _fullNameController = TextEditingController(text: 'Nguyễn Văn Con');
  final _phoneController = TextEditingController(text: '0988888888');

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        await CaregiverApiService.instance.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await CaregiverApiService.instance.register(
          fullName: _fullNameController.text,
          phoneNumber: _phoneController.text,
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmailCtrl = TextEditingController(
      text: _emailController.text.trim(),
    );
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    int currentStep = 1; // 1: Email, 2: OTP + New Password
    bool isProcessing = false;
    String? dialogError;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_reset, color: Color(0xFF4A3020)),
              const SizedBox(width: 8),
              Text(
                currentStep == 1 ? 'Quên Mật Khẩu' : 'Đặt Lại Mật Khẩu',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentStep == 1) ...[
                  const Text(
                    'Nhập địa chỉ email đăng ký để nhận mã OTP 6 số (TTL 10 phút):',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7D7168)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: resetEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email của bạn',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                ] else ...[
                  Text(
                    'Mã OTP đã được gửi tới email ${resetEmailCtrl.text.trim()}. Vui lòng kiểm tra hộp thư:',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7D7168),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      labelText: 'Mã OTP 6 số',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    dialogError!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A3020),
                foregroundColor: Colors.white,
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                      final email = resetEmailCtrl.text.trim();
                      if (email.isEmpty) return;

                      if (currentStep == 1) {
                        setDState(() {
                          isProcessing = true;
                          dialogError = null;
                        });
                        try {
                          await CaregiverApiService.instance.forgotPassword(
                            email,
                          );
                          setDState(() {
                            isProcessing = false;
                            currentStep = 2;
                          });
                        } catch (e) {
                          setDState(() {
                            isProcessing = false;
                            dialogError = e
                                .toString()
                                .replaceAll('Exception:', '')
                                .trim();
                          });
                        }
                      } else {
                        final otp = otpCtrl.text.trim();
                        final newPass = newPassCtrl.text.trim();
                        if (otp.isEmpty || newPass.isEmpty) {
                          setDState(
                            () => dialogError =
                                'Vui lòng điền đủ OTP và mật khẩu mới.',
                          );
                          return;
                        }

                        setDState(() {
                          isProcessing = true;
                          dialogError = null;
                        });
                        try {
                          await CaregiverApiService.instance.resetPassword(
                            email: email,
                            otpCode: otp,
                            newPassword: newPass,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          _passwordController.text = newPass;
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã đặt lại mật khẩu thành công! Bạn có thể đăng nhập ngay.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDState(() {
                            isProcessing = false;
                            dialogError = e
                                .toString()
                                .replaceAll('Exception:', '')
                                .trim();
                          });
                        }
                      }
                    },
              child: isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      currentStep == 1 ? 'Gửi Mã OTP' : 'Xác Nhận Đổi Mật Khẩu',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showGreetingIllustration =
        MediaQuery.sizeOf(context).width >= 360 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Quay lại chọn vai trò',
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(RoleSelectionScreen.prefSelectedRole);
            if (!context.mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Cài đặt máy chủ',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ServerConfigDialog(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 24, 12, 0),
                    decoration: const BoxDecoration(
                      color: CareAiColors.sageLight,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                        bottomLeft: Radius.circular(72),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CareAiBrand(
                          subtitle: 'Một kết nối, triệu yêu thương',
                        ),
                        const SizedBox(height: 22),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Text(
                                  _isLogin
                                      ? 'Chào mừng\nbạn trở lại.'
                                      : 'Cùng chăm sóc\nngười thương.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium,
                                ),
                              ),
                            ),
                            if (showGreetingIllustration)
                              Image.asset(
                                'assets/images/facare/girl-greeting-clean.png',
                                width: 112,
                                height: 145,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('Đăng nhập')),
                      ButtonSegment(value: false, label: Text('Đăng ký')),
                    ],
                    selected: {_isLogin},
                    showSelectedIcon: false,
                    onSelectionChanged: _isLoading
                        ? null
                        : (value) => setState(() => _isLogin = value.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: CareAiColors.brown,
                      selectedForegroundColor: Colors.white,
                      backgroundColor: CareAiColors.muted,
                      foregroundColor: CareAiColors.brown,
                      minimumSize: const Size(48, 50),
                      side: BorderSide.none,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    _isLogin
                        ? 'Đăng nhập để kết nối với gia đình.'
                        : 'Tạo tài khoản người thân để bắt đầu.',
                    style: const TextStyle(
                      color: CareAiColors.secondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_isLogin) ...[
                    TextField(
                      controller: _fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Địa chỉ email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  if (_isLogin)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : _showForgotPasswordDialog,
                        child: const Text('Quên mật khẩu?'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (_errorMessage != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: CareAiColors.dangerSurface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: CareAiColors.danger,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: CareAiColors.danger,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _isLogin ? 'Đăng nhập' : 'Tạo tài khoản',
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Chăm sóc từ xa, yêu thương gần hơn.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
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
