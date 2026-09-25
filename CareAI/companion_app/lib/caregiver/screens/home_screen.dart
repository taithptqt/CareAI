import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import 'elder_dashboard_screen.dart';
import 'incident_detail_screen.dart';
import 'login_screen.dart';
import 'server_config_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../screens/device_pairing_screen.dart';
import '../../screens/role_selection_screen.dart';
import '../../screens/sos_button_screen.dart';
import '../../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  String _caregiverName = 'Người Thân';
  String _caregiverEmail = '';

  // Dữ liệu
  List<ElderItem> _elders = [];
  List<Incident> _activeIncidents = [];
  bool _isLoadingElders = true;
  bool _isLoadingIncidents = false;

  // Polling sự cố
  Timer? _alertPollingTimer;
  Incident? _currentEmergency;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadElders();
    _loadActiveIncidents();
    _startAlertPolling();
  }

  @override
  void dispose() {
    _alertPollingTimer?.cancel();
    super.dispose();
  }

  void _startAlertPolling() {
    _alertPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) return;
      try {
        final incidents = await CaregiverApiService.instance.getActiveIncidents();
        if (mounted) {
          final openInc = incidents.where((i) => i.isOpen).toList();
          setState(() {
            _activeIncidents = incidents;
            if (openInc.isNotEmpty) {
              if (_currentEmergency?.id != openInc.first.id) {
                HapticFeedback.heavyImpact();
              }
              _currentEmergency = openInc.first;
            } else {
              _currentEmergency = null;
            }
          });
        }
      } catch (e) { debugPrint("[CAREGIVER-APP] Polling error: `$e"); }
    });
  }

  Future<void> _loadUserInfo() async {
    final name = await CaregiverApiService.instance.getCaregiverName();
    final email = await CaregiverApiService.instance.getCaregiverEmail();
    if (mounted) {
      setState(() {
        _caregiverName = name ?? 'Người Thân';
        _caregiverEmail = email ?? '';
      });
    }
  }

  Future<void> _loadElders() async {
    setState(() => _isLoadingElders = true);
    try {
      final list = await CaregiverApiService.instance.getMyElders();
      debugPrint("[CAREGIVER-APP] Loaded `${list.length} elders.");
      if (mounted) {
        setState(() {
          _elders = list;
          _isLoadingElders = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingElders = false);
        if (e.toString().contains('hết hạn')) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        }
      }
    }
  }

  Future<void> _loadActiveIncidents() async {
    setState(() => _isLoadingIncidents = true);
    try {
      final list = await CaregiverApiService.instance.getActiveIncidents();
      debugPrint("[CAREGIVER-APP] Loaded `${list.length} incidents.");
      if (mounted) {
        setState(() {
          _activeIncidents = list;
          _isLoadingIncidents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingIncidents = false);
    }
  }

  Future<void> _showAddElderDialog() async {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    DateTime selectedDob = DateTime(1950, 1, 1);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Thêm Hồ Sơ Người Cao Tuổi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ và tên Cụ *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Ngày sinh: ${DateFormat('dd/MM/yyyy').format(selectedDob)}'),
                  trailing: const Icon(Icons.calendar_today, size: 20),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDob,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDState(() => selectedDob = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Tiền sử bệnh lý (tùy chọn)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'SĐT khẩn cấp (tùy chọn)', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await CaregiverApiService.instance.createElder(
                    fullName: nameCtrl.text.trim(),
                    dateOfBirth: selectedDob,
                    medicalNotes: notesCtrl.text.trim(),
                    emergencyContact: phoneCtrl.text.trim(),
                  );
                  _loadElders();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã tạo hồ sơ Cụ thành công!'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Tạo Hồ Sơ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePinForElder(ElderItem elder) async {
    try {
      final pin = await CaregiverApiService.instance.generatePin(elder.id);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Mã PIN Ghép Nối - ${elder.fullName}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Nhập mã 6 số này vào ứng dụng Companion của Cụ:'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF0284C7), width: 2),
                  ),
                  child: Text(
                    pin,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 8, color: Color(0xFF0284C7)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Hiệu lực trong vòng 10 phút', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
            ],
          ),
        );
        _loadElders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi sinh PIN: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('CareAI Người Thân', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadElders();
              _loadActiveIncidents();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => const ServerConfigDialog(),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Cảnh Báo Khẩn Cấp Bật Ngay Khi Cụ Ngã (UC-08 Quorum Alerting)
          if (_currentEmergency != null) _buildStickyEmergencyAlert(),

          // Nội dung theo Tab
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildEldersTab(),
                _buildIncidentsTab(),
                _buildProfileTab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: Color(0xFF0284C7)),
            label: 'Người Cao Tuổi',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _activeIncidents.any((i) => i.isOpen),
              label: Text('${_activeIncidents.where((i) => i.isOpen).length}'),
              child: const Icon(Icons.notification_important_outlined),
            ),
            selectedIcon: const Icon(Icons.notification_important, color: Color(0xFFDC2626)),
            label: 'Sự Cố Cứu Hộ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFF0284C7)),
            label: 'Tài Khoản',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add),
              label: const Text('Thêm Cụ'),
              onPressed: _showAddElderDialog,
            )
          : null,
    );
  }

  Widget _buildStickyEmergencyAlert() {
    final inc = _currentEmergency!;
    final isFall = inc.emergencyType == 'FALL_DETECTED';

    return GestureDetector(
      onTap: () async {
        final changed = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc)),
        );
        if (changed == true) {
          _loadActiveIncidents();
        }
      },
      child: Container(
        width: double.infinity,
        color: const Color(0xFFDC2626),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFall ? '🚨 CỤ ${inc.elderName.toUpperCase()} BỊ TÉ NGÃ!' : '🚨 CỤ ${inc.elderName.toUpperCase()} PHÁT SOS!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Text('Chạm vào để xem chi tiết và tiếp nhận cứu hộ ngay', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildEldersTab() {
    if (_isLoadingElders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_elders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            const Text('Chưa có hồ sơ người cao tuổi nào', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Thêm Hồ Sơ Đầu Tiên', style: TextStyle(color: Colors.white)),
              onPressed: _showAddElderDialog,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadElders,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: _elders.length,
        itemBuilder: (ctx, idx) {
          final elder = _elders[idx];
          final isOnline = elder.deviceStatus == 'ONLINE';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ElderDashboardScreen(elderProfileId: elder.id, elderName: elder.fullName),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFFE0F2FE),
                          child: Text(
                            elder.fullName.isNotEmpty ? elder.fullName[0].toUpperCase() : 'C',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0284C7)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                elder.fullName,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 2),
                              Text('${elder.age} tuổi', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOnline ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isOnline ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isOnline ? Colors.green[800] : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.key, size: 16, color: Color(0xFF0284C7)),
                          label: const Text('Sinh Mã PIN Ghép Nối', style: TextStyle(color: Color(0xFF0284C7), fontSize: 12)),
                          onPressed: () => _generatePinForElder(elder),
                        ),
                        const Row(
                          children: [
                            Text('Xem Chỉ Số', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0284C7))),
                            Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF0284C7)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIncidentsTab() {
    if (_isLoadingIncidents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeIncidents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: Colors.green[400]),
            const SizedBox(height: 12),
            const Text('Hệ Thống An Toàn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(height: 4),
            const Text('Hiện không có sự cố khẩn cấp nào đang mở.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActiveIncidents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeIncidents.length,
        itemBuilder: (ctx, idx) {
          final inc = _activeIncidents[idx];
          final isOpen = inc.isOpen;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: isOpen ? 3 : 1,
            color: isOpen ? const Color(0xFFFEF2F2) : Colors.white,
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              leading: CircleAvatar(
                backgroundColor: isOpen ? const Color(0xFFDC2626) : Colors.amber[700],
                child: Icon(
                  inc.emergencyType == 'FALL_DETECTED' ? Icons.personal_injury : Icons.warning,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(
                inc.emergencyType == 'FALL_DETECTED' ? 'Té Ngã - ${inc.elderName}' : 'SOS - ${inc.elderName}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Thời gian: ${DateFormat('HH:mm:ss dd/MM').format(inc.triggeredAt.toLocal())}'),
                  const SizedBox(height: 2),
                  Text(
                    isOpen ? 'Trạng thái: CHƯA TIẾP NHẬN' : 'Trạng thái: ĐÃ TIẾP NHẬN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isOpen ? Colors.red[700] : Colors.amber[800],
                    ),
                  ),
                ],
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc)),
                );
                if (changed == true) {
                  _loadActiveIncidents();
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: const Color(0xFFE0F2FE),
            child: const Icon(Icons.person, size: 40, color: Color(0xFF0284C7)),
          ),
          const SizedBox(height: 12),
          Text(
            _caregiverName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
          Text(_caregiverEmail, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
          const SizedBox(height: 24),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined, color: Color(0xFF0284C7)),
                  title: const Text('Cài đặt máy chủ Backend'),
                  subtitle: Text(CaregiverApiService.instance.currentServerUrl, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const ServerConfigDialog(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Color(0xFF0284C7)),
                  title: const Text('Phiên bản hệ thống'),
                  subtitle: const Text('CareAI v111.0 Production Edition'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.personal_injury_rounded, color: Color(0xFFEF4444)),
                  title: const Text('Chuyển sang Chế độ Người cao tuổi'),
                  subtitle: const Text('Kích hoạt nút SOS & Cảnh báo ngã trên máy này'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _switchToElderMode,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.switch_account_rounded, color: Color(0xFF64748B)),
                  title: const Text('Màn hình chọn vai trò'),
                  subtitle: const Text('Quay lại màn hình khởi đầu để chọn vai trò khác'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _goToRoleSelection,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('ĐĂNG XUẤT', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                await CaregiverApiService.instance.logout();
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Future<void> _switchToElderMode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển sang Chế độ Người cao tuổi?'),
        content: const Text(
          'Thiết bị sẽ chuyển sang màn hình Cứu nạn khẩn cấp SOS và kích hoạt cảm biến té ngã.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('CHUYỂN SANG CỤ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(RoleSelectionScreen.prefSelectedRole, 'elder');
      final isPaired = await ApiService.instance.isPaired();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => isPaired ? const SosButtonScreen() : const DevicePairingScreen(),
        ),
      );
    }
  }

  Future<void> _goToRoleSelection() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(RoleSelectionScreen.prefSelectedRole);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
  }
}
