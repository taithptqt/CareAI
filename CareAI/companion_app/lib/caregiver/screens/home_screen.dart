import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import '../services/caregiver_push_service.dart';
import '../services/place_search_service.dart';
import '../widgets/home_address_field.dart';
import 'elder_dashboard_screen.dart';
import 'incident_detail_screen.dart';
import 'incident_history_screen.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _alarm = MethodChannel('vn.careai.companion/caregiver_alarm');
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
  final Map<String, int> _alarmCycles = {};
  bool _refreshingIncidents = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
    _loadElders();
    _loadActiveIncidents();
    _startAlertPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      CaregiverPushService.instance.registerCurrentToken();
      CaregiverPushService.instance.openPendingIncident();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertPollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_loadActiveIncidents());
  }

  void _startAlertPolling() {
    _alertPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadActiveIncidents());
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
    if (_refreshingIncidents) return;
    _refreshingIncidents = true;
    try {
      final list = await CaregiverApiService.instance.getActiveIncidents();
      debugPrint("[CAREGIVER-APP] Loaded `${list.length} incidents.");
      if (mounted) {
        final emergencies = list.where((i) => i.isOpen && i.severity == 'Critical').toList();
        final first = emergencies.isEmpty ? null : emergencies.first;
        if (first != null && _currentEmergency?.id != first.id) {
          HapticFeedback.heavyImpact();
        }
        setState(() {
          _activeIncidents = list;
          _currentEmergency = first;
          _isLoadingIncidents = false;
        });
        await _syncEmergencyAlarms(emergencies);
      }
    } catch (error) {
      debugPrint('[CAREGIVER-APP] Không thể tải sự cố: $error');
      if (mounted) setState(() => _isLoadingIncidents = false);
    } finally {
      _refreshingIncidents = false;
    }
  }

  Future<void> _syncEmergencyAlarms(List<Incident> emergencies) async {
    final currentIds = emergencies.map((i) => i.id).toSet();
    for (final id in _alarmCycles.keys.toList()) {
      if (currentIds.contains(id)) continue;
      final cycle = _alarmCycles.remove(id)!;
      try {
        await _alarm.invokeMethod<void>('stop', {
          'incidentId': id, 'alertCycleNumber': cycle,
        });
      } catch (error) {
        debugPrint('[CAREGIVER-APP] Không thể dừng còi: $error');
      }
    }
    for (final incident in emergencies) {
      final cycle = incident.alertState?.cycleNumber ?? 1;
      if ((_alarmCycles[incident.id] ?? -1) >= cycle) continue;
      try {
        await _alarm.invokeMethod<void>('start', {
          'incidentId': incident.id,
          'alertCycleNumber': cycle,
          'title': 'CẤP CỨU: ${incident.elderName}',
          'body': _emergencyDescription(incident),
          'emergencyType': incident.emergencyType,
        });
        _alarmCycles[incident.id] = cycle;
      } on MissingPluginException {
        // Flutter widget tests and platforms other than Android have no native siren.
      } catch (error) {
        debugPrint('[CAREGIVER-APP] Không thể bật còi: $error');
      }
    }
  }

  String _emergencyDescription(Incident incident) => incident.emergencyType == 'FALL'
      ? '${incident.elderName} vừa bị ngã. Cần kiểm tra và tiếp nhận ngay.'
      : '${incident.elderName} đang cần trợ giúp khẩn cấp. Hãy tiếp nhận ngay.';

  Future<void> _showAddElderDialog() async {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    var homeAddress = '';
    PlaceSuggestion? homePlace;
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
                const SizedBox(height: 12),
                HomeAddressField(
                  onChanged: (value) => homeAddress = value,
                  onPlaceSelected: (place) => homePlace = place,
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
                    homeAddress: homeAddress.trim(),
                    homeLatitude: homePlace?.latitude,
                    homeLongitude: homePlace?.longitude,
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

  Future<void> _editHomeAddress(ElderItem elder) async {
    var editedAddress = elder.homeAddress ?? '';
    PlaceSuggestion? editedPlace = elder.homeLatitude != null &&
            elder.homeLongitude != null
        ? PlaceSuggestion(editedAddress,
            latitude: elder.homeLatitude, longitude: elder.homeLongitude)
        : null;
    final address = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Địa chỉ nhà của ${elder.fullName}'),
      content: SingleChildScrollView(
        child: HomeAddressField(
          initialValue: editedAddress,
          initialLatitude: elder.homeLatitude,
          initialLongitude: elder.homeLongitude,
          onChanged: (value) => editedAddress = value,
          onPlaceSelected: (place) => editedPlace = place,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, editedAddress.trim()),
          child: const Text('Lưu địa chỉ')),
      ],
    ));
    if (address == null || !mounted) return;
    try {
      await CaregiverApiService.instance.updateElderHomeAddress(elder.id, address,
        latitude: editedPlace?.latitude, longitude: editedPlace?.longitude);
      if (mounted) await _loadElders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể lưu địa chỉ: $error')));
      }
    }
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
            icon: const Icon(Icons.history),
            tooltip: 'Lịch sử sự cố',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IncidentHistoryScreen()),
            ),
          ),
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
    final isFall = inc.emergencyType == 'FALL';
    final count = _activeIncidents.where((i) => i.isOpen && i.severity == 'Critical').length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(color: Color(0xFFB91C1C)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.notification_important, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('BÁO ĐỘNG KHẨN CẤP', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 8),
          Text(
            '${inc.elderName} ${isFall ? 'vừa bị ngã' : 'cần trợ giúp ngay'}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'Chưa ai tiếp nhận • ${DateFormat('HH:mm, dd/MM').format(inc.triggeredAt.toLocal())}'
            '${count > 1 ? ' • $count sự cố khẩn' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF991B1B),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              final changed = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc)),
              );
              if (changed == true) unawaited(_loadActiveIncidents());
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('XEM VÀ TIẾP NHẬN SỰ CỐ',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
                    Row(children: [
                      const Icon(Icons.home_outlined, size: 17, color: Color(0xFF475569)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        elder.homeAddress?.isNotEmpty == true
                            ? elder.homeAddress! : 'Chưa có địa chỉ nhà để cứu hộ',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      )),
                      TextButton(onPressed: () => _editHomeAddress(elder),
                        child: const Text('Sửa')),
                    ]),
                    const Divider(height: 12),
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
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Tra cứu lịch sử sự cố'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const IncidentHistoryScreen()),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadActiveIncidents,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _activeIncidents.length + 1,
        itemBuilder: (ctx, idx) {
          if (idx == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Sự cố đang xử lý', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                  TextButton.icon(
                    icon: const Icon(Icons.history, size: 16, color: Color(0xFF0284C7)),
                    label: const Text('Xem lịch sử', style: TextStyle(fontSize: 12, color: Color(0xFF0284C7))),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const IncidentHistoryScreen()),
                    ),
                  ),
                ],
              ),
            );
          }
          final inc = _activeIncidents[idx - 1];
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
                  inc.emergencyType == 'FALL' ? Icons.personal_injury : Icons.warning,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              title: Text(
                inc.emergencyType == 'FALL' ? 'Té Ngã - ${inc.elderName}' : 'Khẩn cấp - ${inc.elderName}',
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
                await CaregiverPushService.instance.unregisterCurrentToken();
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
      await CaregiverPushService.instance.unregisterCurrentToken();
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
    await CaregiverPushService.instance.unregisterCurrentToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(RoleSelectionScreen.prefSelectedRole);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
    );
  }
}
