import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../screens/role_selection_screen.dart';
import '../services/caregiver_api_service.dart';
import 'home_screen.dart';
import 'server_config_dialog.dart';

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
    final resetEmailCtrl = TextEditingController(text: _emailController.text.trim());
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
              const Icon(Icons.lock_reset, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(currentStep == 1 ? 'Quên Mật Khẩu' : 'Đặt Lại Mật Khẩu', style: const TextStyle(fontSize: 16)),
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
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
                  Text(dialogError!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
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
                          await CaregiverApiService.instance.forgotPassword(email);
                          setDState(() {
                            isProcessing = false;
                            currentStep = 2;
                          });
                        } catch (e) {
                          setDState(() {
                            isProcessing = false;
                            dialogError = e.toString().replaceAll('Exception:', '').trim();
                          });
                        }
                      } else {
                        final otp = otpCtrl.text.trim();
                        final newPass = newPassCtrl.text.trim();
                        if (otp.isEmpty || newPass.isEmpty) {
                          setDState(() => dialogError = 'Vui lòng điền đủ OTP và mật khẩu mới.');
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
                                content: Text('Đã đặt lại mật khẩu thành công! Bạn có thể đăng nhập ngay.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          setDState(() {
                            isProcessing = false;
                            dialogError = e.toString().replaceAll('Exception:', '').trim();
                          });
                        }
                      }
                    },
              child: isProcessing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(currentStep == 1 ? 'Gửi Mã OTP' : 'Xác Nhận Đổi Mật Khẩu'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1E293B)),
          tooltip: 'Quay lại Chọn vai trò',
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
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF1E293B)),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo & Header
                Image.asset(
                  'assets/images/logo.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                const Text(
                  'CareAI',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ứng Dụng Giám Sát Sức Khỏe Cho Người Thân',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 28),

                // Form Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Segmented Tab
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _isLogin = true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _isLogin ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: _isLogin
                                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                          : null,
                                    ),
                                    child: Text(
                                      'Đăng Nhập',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: _isLogin ? FontWeight.bold : FontWeight.w500,
                                        color: _isLogin ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _isLogin = false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: !_isLogin ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: !_isLogin
                                          ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
                                          : null,
                                    ),
                                    child: Text(
                                      'Đăng Ký Mới',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: !_isLogin ? FontWeight.bold : FontWeight.w500,
                                        color: !_isLogin ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Trường Đăng ký
                        if (!_isLogin) ...[
                          TextField(
                            controller: _fullNameController,
                            decoration: const InputDecoration(
                              labelText: 'Họ và Tên',
                              prefixIcon: Icon(Icons.person_outline),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Số Điện Thoại',
                              prefixIcon: Icon(Icons.phone_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Trường Email
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Địa chỉ Email',
                            prefixIcon: Icon(Icons.email_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Trường Mật khẩu
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        if (_isLogin)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _showForgotPasswordDialog,
                              child: const Text(
                                'Quên mật khẩu?',
                                style: TextStyle(fontSize: 12, color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),

                        // Báo lỗi nếu có
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Nút Submit
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  _isLogin ? 'ĐĂNG NHẬP' : 'TẠO TÀI KHOẢN MỚI',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Kết nối: ${CaregiverApiService.instance.currentServerUrl}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
