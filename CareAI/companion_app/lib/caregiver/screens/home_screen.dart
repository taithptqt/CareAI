import '../../theme/careai_theme.dart';
import '../../widgets/careai_ui.dart';

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import '../services/caregiver_push_service.dart';
import '../services/power_optimization_service.dart';
import '../services/place_search_service.dart';
import '../widgets/home_address_field.dart';
import '../widgets/family_overview.dart';
import 'elder_dashboard_screen.dart';
import 'incident_detail_screen.dart';
import 'incident_history_screen.dart';
import 'login_screen.dart';
import 'server_config_dialog.dart';
import 'family_management_screen.dart';
import 'elder_edit_dialog.dart';
import 'feedback_screen.dart';

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
  final Map<String, int> _silencedIncidentCycles = {};
  bool _refreshingIncidents = false;
  CriticalPermissionsStatus? _permissionStatus;
  bool _isPermissionDialogShowing = false;
  bool _isRequestingPermissions = false;
  bool _hasUserCompletedOrDismissedOnboarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
    _loadElders();
    _loadActiveIncidents();
    _startAlertPolling();
    CaregiverApiService.instance.sessionExpiredNotifier.addListener(_handleSessionExpired);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      CaregiverPushService.instance.registerCurrentToken();
      CaregiverPushService.instance.openPendingIncident();
      await _checkAndRequestPermissionsSequentially();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alertPollingTimer?.cancel();
    CaregiverApiService.instance.sessionExpiredNotifier.removeListener(_handleSessionExpired);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadActiveIncidents());
      // Cập nhật ngầm trạng thái quyền, tuyệt đối không tự ý bung popup đè lên khi app resume
      if (!_isRequestingPermissions && !_isPermissionDialogShowing) {
        unawaited(_checkCriticalPermissionsRealtime(showPopupIfMissing: false));
      }
    }
  }

  void _handleSessionExpired() {
    if (CaregiverApiService.instance.sessionExpiredNotifier.value && mounted) {
      CaregiverApiService.instance.sessionExpiredNotifier.value = false;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Tài khoản của bạn đã bị tạm ngưng hoặc phiên đăng nhập đã hết hạn.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
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
        final emergencies = list
            .where((i) => i.isOpen && i.severity == 'Critical')
            .toList();
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

  bool _isEmergencySilenced(Incident inc) {
    final cycle = inc.alertState?.cycleNumber ?? 1;
    return (_silencedIncidentCycles[inc.id] ?? -1) >= cycle;
  }

  Future<void> _silenceCurrentAlarm(Incident incident) async {
    final cycle = incident.alertState?.cycleNumber ?? 1;
    _silencedIncidentCycles[incident.id] = cycle;
    try {
      await _alarm.invokeMethod<void>('stop', {
        'incidentId': incident.id,
        'alertCycleNumber': cycle,
      });
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _syncEmergencyAlarms(List<Incident> emergencies) async {
    final currentIds = emergencies.map((i) => i.id).toSet();
    _silencedIncidentCycles.removeWhere((id, _) => !currentIds.contains(id));
    for (final id in _alarmCycles.keys.toList()) {
      if (currentIds.contains(id)) continue;
      final cycle = _alarmCycles.remove(id)!;
      try {
        await _alarm.invokeMethod<void>('stop', {
          'incidentId': id,
          'alertCycleNumber': cycle,
        });
      } catch (error) {
        debugPrint('[CAREGIVER-APP] Không thể dừng còi: $error');
      }
    }
    for (final incident in emergencies) {
      final cycle = incident.alertState?.cycleNumber ?? 1;
      // Tuân thủ chuẩn báo động y tế IEC 60601-1-8: nếu chu kỳ hiện tại đã được người thân tắt còi, không hú lại;
      // Nhưng nếu sự cố leo thang chu kỳ mới (cycle tăng sau SLA 60s), còi sẽ được phép hú lại.
      if ((_silencedIncidentCycles[incident.id] ?? -1) >= cycle) continue;
      if ((_alarmCycles[incident.id] ?? -1) >= cycle) continue;
      try {
        await _alarm.invokeMethod<void>('start', {
          'incidentId': incident.id,
          'alertCycleNumber': cycle,
          'title': _emergencyAlarmTitle(incident),
          'body': _emergencyDescription(incident),
          'emergencyType': incident.emergencyType,
        });
        _alarmCycles[incident.id] = cycle;
      } on MissingPluginException {
        // Fallback khi chạy Flutter widget tests không có kênh native siren (iOS và Android đã hỗ trợ đầy đủ).
      } catch (error) {
        debugPrint('[CAREGIVER-APP] Không thể bật còi: $error');
      }
    }
  }

  String _emergencyAlarmTitle(Incident incident) {
    final type = incident.emergencyType.toUpperCase();
    if (type.contains('STALE') || type.contains('OFFLINE')) {
      return 'MẤT TÍN HIỆU: ${incident.elderName}';
    }
    if (type.contains('FALL')) {
      return 'TÉ NGÃ: ${incident.elderName}';
    }
    if (type.contains('LOW_OXYGEN') ||
        type.contains('LOWOXYGEN') ||
        type.contains('OXYGEN') ||
        type.contains('SPO2')) {
      return 'SPO2 THẤP: ${incident.elderName}';
    }
    if (type.contains('TACHYCARDIA')) {
      return 'NHỊP TIM NHANH: ${incident.elderName}';
    }
    if (type.contains('BRADYCARDIA')) {
      return 'NHỊP TIM CHẬM: ${incident.elderName}';
    }
    if (type.contains('SURGE')) {
      return 'TIM TĂNG VỌT: ${incident.elderName}';
    }
    if (type.contains('HYPERTENSION')) {
      return 'TĂNG HUYẾT ÁP: ${incident.elderName}';
    }
    return 'CẤP CỨU: ${incident.elderName}';
  }

  String _emergencyDescription(Incident incident) {
    final type = incident.emergencyType.toUpperCase();
    if (type.contains('FALL')) {
      return '${incident.elderName} vừa bị ngã. Cần kiểm tra và tiếp nhận ngay.';
    }
    if (type.contains('LOW_OXYGEN') ||
        type.contains('LOWOXYGEN') ||
        type.contains('OXYGEN')) {
      return '${incident.elderName} có nồng độ oxy máu SpO₂ thấp. Cần kiểm tra ngay.';
    }
    if (type.contains('TACHYCARDIA')) {
      return '${incident.elderName} có nhịp tim nhanh nguy hiểm. Cần kiểm tra ngay.';
    }
    if (type.contains('BRADYCARDIA')) {
      return '${incident.elderName} có nhịp tim chậm nguy hiểm. Cần kiểm tra ngay.';
    }
    if (type.contains('SURGE')) {
      return '${incident.elderName} có nhịp tim tăng vọt bất thường. Cần kiểm tra ngay.';
    }
    if (type.contains('HYPERTENSION')) {
      return '${incident.elderName} có dấu hiệu cơn tăng huyết áp nguy hiểm.';
    }
    if (type.contains('STALE') || type.contains('OFFLINE')) {
      return 'Tất cả thiết bị của ${incident.elderName} đã mất tín hiệu kết nối.';
    }
    if (type.contains('SOS')) {
      return '${incident.elderName} đã kích hoạt nút cứu hộ khẩn cấp SOS.';
    }
    return '${incident.elderName} đang cần trợ giúp khẩn cấp. Hãy tiếp nhận ngay.';
  }

  IconData _emergencyIcon(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return Icons.warning_rounded;
    if (upper.contains('OXYGEN') || upper.contains('SPO2')) {
      return Icons.air_rounded;
    }
    if (upper.contains('TACHYCARDIA') ||
        upper.contains('BRADYCARDIA') ||
        upper.contains('SURGE') ||
        upper.contains('HR') ||
        upper.contains('HEART')) {
      return Icons.monitor_heart_rounded;
    }
    if (upper.contains('HYPERTENSION') || upper.contains('BLOOD_PRESSURE')) {
      return Icons.speed_rounded;
    }
    if (upper.contains('STALE') || upper.contains('OFFLINE')) {
      return Icons.wifi_off_rounded;
    }
    if (upper.contains('SOS')) return Icons.emergency_rounded;
    return Icons.warning_amber_rounded;
  }

  String _emergencyLabel(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return 'Té Ngã';
    if (upper.contains('LOW_OXYGEN') ||
        upper.contains('LOWOXYGEN') ||
        upper.contains('OXYGEN')) {
      return 'Oxy Máu Thấp';
    }
    if (upper.contains('TACHYCARDIA')) return 'Nhịp Tim Nhanh';
    if (upper.contains('BRADYCARDIA')) return 'Nhịp Tim Chậm';
    if (upper.contains('SURGE')) return 'Nhịp Tim Tăng Vọt';
    if (upper.contains('HYPERTENSION')) return 'Cơn Tăng Huyết Áp';
    if (upper.contains('STALE') || upper.contains('OFFLINE')) {
      return 'Mất Tín Hiệu';
    }
    if (upper.contains('SOS')) return 'Nút Khẩn Cấp SOS';
    return type;
  }

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
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: const Text('Thêm người thân'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Họ và tên *'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Ngày sinh: ${DateFormat('dd/MM/yyyy').format(selectedDob)}',
                    style: const TextStyle(fontSize: 14),
                  ),
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
                  decoration: const InputDecoration(
                    labelText: 'Tiền sử bệnh lý',
                    helperText: 'Không bắt buộc',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số khẩn cấp',
                    helperText: 'Không bắt buộc',
                  ),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A3020),
              ),
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
                      const SnackBar(
                        content: Text(
                          'Đã tạo hồ sơ Người cao tuổi thành công!',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Tạo hồ sơ',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editHomeAddress(ElderItem elder) async {
    var editedAddress = elder.homeAddress ?? '';
    PlaceSuggestion? editedPlace =
        elder.homeLatitude != null && elder.homeLongitude != null
        ? PlaceSuggestion(
            editedAddress,
            latitude: elder.homeLatitude,
            longitude: elder.homeLongitude,
          )
        : null;
    final address = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, editedAddress.trim()),
            child: const Text('Lưu địa chỉ'),
          ),
        ],
      ),
    );
    if (address == null || !mounted) return;
    try {
      await CaregiverApiService.instance.updateElderHomeAddress(
        elder.id,
        address,
        latitude: editedPlace?.latitude,
        longitude: editedPlace?.longitude,
      );
      if (mounted) await _loadElders();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể lưu địa chỉ: $error')),
        );
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
                const Text(
                  'Nhập mã 6 số này vào ứng dụng Companion của Người cao tuổi:',
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8E5DC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF4A3020),
                      width: 2,
                    ),
                  ),
                  child: Text(
                    pin,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Color(0xFF4A3020),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Hiệu lực trong vòng 15 phút (Lưu băm SHA-256 an toàn)',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
        _loadElders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditElderDialog(ElderItem elder) {
    showDialog(
      context: context,
      builder: (_) => ElderEditDialog(
        elder: elder,
        onUpdated: () => _loadElders(),
        onDeleted: () => _loadElders(),
      ),
    );
  }

  Future<void> _showAcceptInvitationDialog() async {
    final codeCtrl = TextEditingController();
    String? dialogError;
    bool isAccepting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.group_add, color: Color(0xFF4A3020)),
              SizedBox(width: 8),
              Text('Tham Gia Nhóm Gia Đình', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Nhập mã mời 6 ký tự do Người bảo hộ chính cung cấp:',
                style: TextStyle(fontSize: 12, color: Color(0xFF7D7168)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: const InputDecoration(
                  labelText: 'Mã Mời (VD: A3X7K2)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                ),
              ),
              if (dialogError != null)
                Text(
                  dialogError!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFDC2626),
                  ),
                ),
            ],
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
              onPressed: isAccepting
                  ? null
                  : () async {
                      final code = codeCtrl.text.trim();
                      if (code.isEmpty) return;
                      setDState(() {
                        isAccepting = true;
                        dialogError = null;
                      });
                      try {
                        final res = await CaregiverApiService.instance
                            .acceptFamilyInvitation(code);
                        if (ctx.mounted) Navigator.pop(ctx);
                        _loadElders();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã tham gia nhóm chăm sóc người cao tuổi ${res.elderName} thành công!',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDState(() {
                          isAccepting = false;
                          dialogError = e
                              .toString()
                              .replaceAll('Exception:', '')
                              .trim();
                        });
                      }
                    },
              child: isAccepting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Tham Gia'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 20,
        title: PopupMenuButton<String>(
          tooltip: 'Mở menu CareAI',
          offset: const Offset(0, 52),
          onSelected: (action) {
            switch (action) {
              case 'history':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const IncidentHistoryScreen(),
                  ),
                );
              case 'invite':
                _showAcceptInvitationDialog();
              case 'refresh':
                _loadElders();
                _loadActiveIncidents();
              case 'settings':
                showDialog(
                  context: context,
                  builder: (_) => const ServerConfigDialog(),
                );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'history', child: Text('Lịch sử sự cố')),
            PopupMenuItem(value: 'invite', child: Text('Nhập mã mời gia đình')),
            PopupMenuItem(value: 'refresh', child: Text('Làm mới dữ liệu')),
            PopupMenuItem(value: 'settings', child: Text('Cài đặt kết nối')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CareAiBrand(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: IconButton(
              tooltip: 'Xem sự cố đang theo dõi',
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: CareAiColors.muted),
              ),
              onPressed: () => setState(() => _currentIndex = 1),
              icon: Badge(
                isLabelVisible: _activeIncidents.any((i) => i.isOpen),
                smallSize: 7,
                child: const Icon(Icons.notifications_none_rounded, size: 22),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner Cảnh Báo Khẩn Cấp Bật Ngay Khi Người Cao Tuổi Ngã (UC-08 Quorum Alerting)
          if (_currentEmergency != null) _buildStickyEmergencyAlert(),

          // Banner Đỏ Cảnh Báo Khi Bị Tắt Quyền Khẩn Cấp (Còi hú bị vô hiệu hóa)
          if (_shouldShowStickyPermissionBanner)
            _buildStickyPermissionWarning(),

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
      bottomNavigationBar: CareAiFamilyDock(
        index: _currentIndex,
        onSelect: (idx) => setState(() => _currentIndex = idx),
        onAdd: _showAddElderDialog,
        onHistory: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const IncidentHistoryScreen()),
        ),
        openIncidents: _activeIncidents.where((i) => i.isOpen).length,
      ),
    );
  }

  Widget _buildStickyEmergencyAlert() {
    final inc = _currentEmergency!;
    final count = _activeIncidents
        .where((i) => i.isOpen && i.severity == 'Critical')
        .length;
    final type = inc.emergencyType.toUpperCase();
    final isStale = type.contains('STALE') || type.contains('OFFLINE');
    final isSilenced = _isEmergencySilenced(inc);

    final headerTitle = isStale ? 'CẢNH BÁO MẤT TÍN HIỆU' : 'BÁO ĐỘNG KHẨN CẤP';
    final headerIcon = isStale
        ? Icons.wifi_off_rounded
        : Icons.notification_important;
    final bannerBg = isStale
        ? const Color(0xFFB45309)
        : const Color(0xFFB91C1C);
    final btnTextColor = isStale
        ? const Color(0xFF92400E)
        : const Color(0xFF991B1B);
    final btnLabel = isStale
        ? 'KIỂM TRA VÀ TIẾP NHẬN SỰ CỐ'
        : 'XEM VÀ TIẾP NHẬN SỰ CỐ';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(color: bannerBg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(headerIcon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                headerTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${inc.elderName} - ${_emergencyLabel(inc.emergencyType)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chưa ai tiếp nhận • ${DateFormat('HH:mm, dd/MM').format(inc.triggeredAt.toLocal())}'
            '${count > 1 ? ' • $count sự cố khẩn' : ''}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (!isSilenced) ...[
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _silenceCurrentAlarm(inc),
                    icon: const Icon(Icons.volume_off_rounded, size: 18),
                    label: const Text(
                      'TẮT CÒI',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: btnTextColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final changed = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => IncidentDetailScreen(
                            incident: inc,
                            initialSilence: isSilenced,
                          ),
                        ),
                      );
                      if (changed == true) unawaited(_loadActiveIncidents());
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text(
                      'XEM & TIẾP NHẬN',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Row(
              children: [
                Icon(Icons.volume_off_rounded, color: Colors.white70, size: 14),
                SizedBox(width: 6),
                Text(
                  'Đã tạm tắt còi hú trên máy này',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: btnTextColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => IncidentDetailScreen(
                      incident: inc,
                      initialSilence: true,
                    ),
                  ),
                );
                if (changed == true) unawaited(_loadActiveIncidents());
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(
                btnLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEldersTab() {
    if (_isLoadingElders) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_elders.isEmpty) {
      return CareAiEmptyState(
        icon: Icons.family_restroom_rounded,
        title: 'Bắt đầu từ người thương',
        description: 'Thêm hồ sơ người cao tuổi hoặc nhập mã mời để cùng gia đình chăm sóc.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: _showAddElderDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Thêm hồ sơ đầu tiên'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _showAcceptInvitationDialog,
              child: const Text('Tôi có mã mời gia đình'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadElders,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          CareAiFamilyOverview(
            caregiverName: _caregiverName,
            elderCount: _elders.length,
            openIncidents: _activeIncidents.where((i) => i.isOpen).length,
            isLoadingIncidents: _isLoadingIncidents,
            onIncidents: () => setState(() => _currentIndex = 1),
          ),
          const SizedBox(height: 24),
          CareAiSectionHeading(
            'Người thân yêu',
            subtitle: 'Chọn hồ sơ để xem thông tin sức khỏe.',
            trailing: IconButton(
              onPressed: _showAddElderDialog,
              tooltip: 'Thêm hồ sơ',
              icon: const Icon(
                Icons.add_circle_outline_rounded,
                color: CareAiColors.brown,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ..._elders.map((elder) {
            final isOnline = elder.deviceStatus == 'ONLINE';
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ElderDashboardScreen(
                        elderProfileId: elder.id,
                        elderName: elder.fullName,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 27,
                              backgroundColor: CareAiColors.peach,
                              child: Text(
                                elder.fullName.isNotEmpty
                                    ? elder.fullName[0].toUpperCase()
                                    : 'C',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: CareAiColors.brown,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    elder.fullName,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: CareAiColors.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    '${elder.age} tuổi',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: CareAiColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: CareAiColors.secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              isOnline
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.wifi_off_rounded,
                              size: 17,
                              color: isOnline
                                  ? CareAiColors.greenInk
                                  : CareAiColors.secondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isOnline
                                    ? 'Thiết bị đang kết nối'
                                    : 'Thiết bị chưa kết nối',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isOnline
                                      ? CareAiColors.greenInk
                                      : CareAiColors.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.home_outlined,
                              size: 18,
                              color: CareAiColors.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                elder.homeAddress?.isNotEmpty == true
                                    ? elder.homeAddress!
                                    : 'Chưa thêm địa chỉ nhà',
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: CareAiColors.secondary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _editHomeAddress(elder),
                              tooltip: 'Sửa địa chỉ nhà',
                              icon: const Icon(
                                Icons.edit_outlined,
                                size: 19,
                                color: CareAiColors.brown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: () => _generatePinForElder(elder),
                              icon: const Icon(Icons.key_rounded, size: 18),
                              label: const Text('Ghép thiết bị'),
                            ),
                            TextButton.icon(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FamilyManagementScreen(
                                    elderId: elder.id,
                                    elderName: elder.fullName,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.groups_outlined, size: 18),
                              label: const Text('Gia đình'),
                            ),
                            IconButton(
                              onPressed: () => _showEditElderDialog(elder),
                              tooltip: 'Chỉnh sửa hồ sơ',
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: CareAiColors.brown,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildIncidentsTab() {
    if (_isLoadingIncidents) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_activeIncidents.isEmpty) {
      return CareAiEmptyState(
        icon: Icons.notifications_none_rounded,
        title: 'Chưa có sự cố đang mở',
        description: 'Các sự cố cần gia đình xử lý sẽ xuất hiện ở đây.',
        action: OutlinedButton.icon(
          icon: const Icon(Icons.history_rounded),
          label: const Text('Xem lịch sử chăm sóc'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const IncidentHistoryScreen()),
          ),
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
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  const Text(
                    'Cần gia đình quan tâm',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF231811),
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(
                      Icons.history,
                      size: 16,
                      color: Color(0xFF4A3020),
                    ),
                    label: const Text(
                      'Xem lịch sử',
                      style: TextStyle(fontSize: 12, color: Color(0xFF4A3020)),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const IncidentHistoryScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          final inc = _activeIncidents[idx - 1];
          final isOpen = inc.isOpen;
          final type = inc.emergencyType.toUpperCase();
          final isStale = type.contains('STALE') || type.contains('OFFLINE');
          final isVitals =
              type.contains('OXYGEN') ||
              type.contains('SPO2') ||
              type.contains('TACHYCARDIA') ||
              type.contains('BRADYCARDIA') ||
              type.contains('SURGE') ||
              type.contains('HYPERTENSION');

          final accent = !isOpen
              ? CareAiColors.greenInk
              : isStale
              ? CareAiColors.amber
              : isVitals
              ? CareAiColors.brown
              : CareAiColors.danger;
          final tint = !isOpen
              ? CareAiColors.greenSurface
              : isStale || isVitals
              ? CareAiColors.peach
              : CareAiColors.dangerSurface;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: CareAiColors.surface,
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  final changed = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IncidentDetailScreen(incident: inc),
                    ),
                  );
                  if (changed == true) {
                    _loadActiveIncidents();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: tint,
                            child: Icon(
                              _emergencyIcon(inc.emergencyType),
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  inc.elderName,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _emergencyLabel(inc.emergencyType),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: CareAiColors.secondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      CareAiStatusLabel(
                        label: isOpen ? 'Chưa tiếp nhận' : 'Đã tiếp nhận',
                        icon: isOpen
                            ? Icons.priority_high_rounded
                            : Icons.check_rounded,
                        color: accent,
                        background: tint,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        DateFormat('HH:mm:ss · dd/MM')
                            .format(inc.triggeredAt.toLocal()),
                        style: const TextStyle(
                          fontSize: 13,
                          color: CareAiColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileTab() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tài khoản của bạn',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: CareAiColors.peach,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white,
                child: Text(
                  _caregiverName.isNotEmpty
                      ? _caregiverName[0].toUpperCase()
                      : 'C',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: CareAiColors.brown,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _caregiverName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: CareAiColors.ink,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _caregiverEmail,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: CareAiColors.brown,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const CareAiSectionHeading('Cách bạn dùng CareAI'),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _profileOption(
                Icons.elderly_rounded,
                'Dùng cho người cao tuổi',
                'Mở nút SOS và theo dõi ngã trên thiết bị này.',
                _switchToElderMode,
              ),
              const Divider(height: 1, indent: 18, endIndent: 18),
              _profileOption(
                Icons.switch_account_outlined,
                'Chọn lại vai trò',
                'Quay về màn hình lựa chọn ban đầu.',
                _goToRoleSelection,
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const CareAiSectionHeading('Kết nối & hỗ trợ'),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _profileOption(
                Icons.notifications_active_outlined,
                'Thiết lập cảnh báo',
                'Hướng dẫn quyền thông báo và hoạt động nền.',
                _showBatteryOptimizationGuide,
              ),
              const Divider(height: 1, indent: 18, endIndent: 18),
              _profileOption(
                Icons.shield_outlined,
                'Thông tin y tế & quyền riêng tư',
                'Tìm hiểu phạm vi hỗ trợ và bảo vệ dữ liệu.',
                _showMedicalDisclaimerDialog,
              ),
              const Divider(height: 1, indent: 18, endIndent: 18),
              _profileOption(
                Icons.feedback_outlined,
                'Góp ý & phản hồi',
                'Gửi góp ý và xem phản hồi bạn đã gửi.',
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                ),
              ),
              const Divider(height: 1, indent: 18, endIndent: 18),
              _profileOption(
                Icons.settings_input_antenna_rounded,
                'Cài đặt kết nối',
                'Xem và thay đổi địa chỉ kết nối của ứng dụng.',
                () => showDialog(
                  context: context,
                  builder: (_) => const ServerConfigDialog(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: CareAiColors.danger,
            side: const BorderSide(color: CareAiColors.border),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Đăng xuất'),
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
        const SizedBox(height: 20),
        const Text(
          'CareAI · Một kết nối, triệu yêu thương',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: CareAiColors.secondary),
        ),
      ],
    ),
  );

  Widget _profileOption(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    leading: Icon(icon, color: CareAiColors.brown, size: 23),
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: CareAiColors.ink,
      ),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: CareAiColors.secondary,
        ),
      ),
    ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      color: CareAiColors.secondary,
    ),
    onTap: onTap,
  );

  Future<void> _switchToElderMode() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển sang Chế độ Người cao tuổi?'),
        content: const Text(
          'Thiết bị sẽ chuyển sang màn hình Cứu nạn khẩn cấp SOS và kích hoạt cảm biến té ngã.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text(
              'CHẾ ĐỘ NGƯỜI CAO TUỔI',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await CaregiverPushService.instance.unregisterCurrentToken();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(RoleSelectionScreen.prefSelectedRole, 'elder');

      // Kiểm tra xem thiết bị này đã liên kết với người cao tuổi thuộc tài khoản Người thân hiện tại hay chưa
      final currentElderProfileId = await ApiService.instance
          .getElderProfileId();
      List<ElderItem> eldersToCheck = _elders;
      if (eldersToCheck.isEmpty) {
        try {
          eldersToCheck = await CaregiverApiService.instance.getMyElders();
        } catch (_) {}
      }

      final bool isLinkedToCurrentCaregiver =
          currentElderProfileId != null &&
          eldersToCheck.any((e) => e.id == currentElderProfileId);

      if (!isLinkedToCurrentCaregiver) {
        // Phía người cao tuổi của tài khoản mới chưa liên kết vào thiết bị -> Hủy ghép đôi cũ và điều hướng sang màn hình nhập PIN
        await ApiService.instance.unpair();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
        );
        return;
      }

      final isPaired = await ApiService.instance.isPaired();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              isPaired ? const SosButtonScreen() : const DevicePairingScreen(),
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

  void _showMedicalDisclaimerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.health_and_safety_outlined, color: Color(0xFF4A3020)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tuyên Bố Y Tế & Pháp Lý',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Định Vị Ứng Dụng (Non-SaMD):',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF231811),
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'CareAI là Nền tảng Hỗ trợ Cảnh báo Chăm sóc Người cao tuổi (Non-SaMD). Hệ thống KHÔNG phải là thiết bị chẩn đoán y tế chuyên sâu và không đưa ra phán quyết điều trị bệnh.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A3020)),
              ),
              SizedBox(height: 12),
              Text(
                '2. Trường Hợp Cấp Cứu Sống Còn:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF231811),
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Trong trường hợp người thân gặp sự cố nguy kịch hoặc tai nạn bất tỉnh, vui lòng gọi ngay Tổng đài Cấp cứu Y tế 115 của Nhà nước hoặc đưa bệnh nhân đến cơ sở y tế gần nhất. CareAI đóng vai trò kênh báo động song song hỗ trợ gia đình.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A3020)),
              ),
              SizedBox(height: 12),
              Text(
                '3. Bảo Vệ Dữ Liệu Sức Khỏe:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF231811),
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Mọi dữ liệu sinh hiệu (nhịp tim, SpO2, gia tốc) đều được truyền mã hóa chuẩn TLS/HTTPS và bảo mật theo quy định tại Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân tại Việt Nam.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4A3020)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'ĐÃ HIỂU & ĐỒNG Ý',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A3020),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkAndRequestPermissionsSequentially() async {
    if (!mounted || _isRequestingPermissions) return;
    _isRequestingPermissions = true;
    try {
      final isFirst = await PowerOptimizationService.instance.isFirstLaunch();

      if (isFirst) {
        // 1. Popup mặc định của điện thoại: Quyền thông báo
        final notifsEnabled = await PowerOptimizationService.instance
            .areNotificationsEnabled();
        if (!notifsEnabled) {
          final canDirect = await PowerOptimizationService.instance
              .canRequestDirectNotificationPermission();
          if (canDirect) {
            // Chờ người dùng phản hồi xong trên popup thông báo của hệ điều hành
            await PowerOptimizationService.instance
                .requestNotificationPermission();
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        // 2. Popup mặc định 1-chạm của điện thoại: Bỏ tối ưu pin
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          final batteryIgnored = await PowerOptimizationService.instance
              .isIgnoringBatteryOptimizations();
          if (!batteryIgnored) {
            // Chờ người dùng phản hồi xong trên popup pin của hệ điều hành
            await PowerOptimizationService.instance
                .requestIgnoreBatteryOptimizations();
            await Future.delayed(const Duration(milliseconds: 300));
          }
        }

        if (!mounted) return;
        final status = await PowerOptimizationService.instance
            .checkCriticalPermissionsStatus();

        // 3. Popup list hướng dẫn các quyền còn lại (CHỈ HIỂN THỊ VÀO LẦN ĐẦU CÀI APP)
        if (_hasItemsToShow(status, isFirst: true) && mounted) {
          await _showPermissionGuideDialog(status, isFirstLaunch: true);
        }

        // Ghi nhận đã qua lần khởi động đầu tiên
        await PowerOptimizationService.instance.dismissOnboarding();
      } else {
        // Các lần mở app sau: TUYỆT ĐỐI KHÔNG hiện popup list!
        // Chỉ nhắc lại nếu quyền tiết kiệm pin bị tắt (bị thu hồi)
        final status = await PowerOptimizationService.instance
            .checkCriticalPermissionsStatus();
        if (!status.batteryOptimizationIgnored &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android) {
          await PowerOptimizationService.instance
              .requestIgnoreBatteryOptimizations();
        }
      }

      if (!mounted) return;
      final status = await PowerOptimizationService.instance
          .checkCriticalPermissionsStatus();
      final hasDismissed = await PowerOptimizationService.instance
          .hasUserDismissedOnboarding();
      setState(() {
        _permissionStatus = status;
        _hasUserCompletedOrDismissedOnboarding = hasDismissed;
      });
    } finally {
      _isRequestingPermissions = false;
    }
  }

  bool _hasItemsToShow(
    CriticalPermissionsStatus status, {
    bool isFirst = false,
  }) {
    if (isFirst) {
      final mfg = status.manufacturer.toLowerCase();
      final isSamsung = mfg.contains('samsung');
      final isChineseOem =
          mfg.contains('xiaomi') ||
          mfg.contains('redmi') ||
          mfg.contains('poco') ||
          mfg.contains('oppo') ||
          mfg.contains('realme') ||
          mfg.contains('vivo') ||
          mfg.contains('huawei') ||
          mfg.contains('honor');

      return !status.notificationsEnabled ||
          !status.batteryOptimizationIgnored ||
          status.backgroundDataRestricted ||
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ||
          isSamsung ||
          isChineseOem;
    }

    // Các lần sau (nếu gọi thủ công từ banner): chỉ hiện nếu có quyền thiết yếu bị thiếu
    return !status.notificationsEnabled ||
        !status.batteryOptimizationIgnored ||
        status.backgroundDataRestricted;
  }

  Future<void> _showBatteryOptimizationGuide() async {
    final status =
        _permissionStatus ??
        await PowerOptimizationService.instance
            .checkCriticalPermissionsStatus();
    await _showPermissionGuideDialog(status, isFirstLaunch: false);
  }

  Future<void> _showPermissionGuideDialog(
    CriticalPermissionsStatus status, {
    bool isFirstLaunch = false,
  }) async {
    if (_isPermissionDialogShowing ||
        !mounted ||
        !_hasItemsToShow(status, isFirst: isFirstLaunch)) {
      return;
    }
    _isPermissionDialogShowing = true;
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _SimplePermissionGuideDialog(
          initialStatus: status,
          isFirstLaunch: isFirstLaunch,
        ),
      );
    } finally {
      _isPermissionDialogShowing = false;
      await _checkCriticalPermissionsRealtime(showPopupIfMissing: false);
    }
  }

  Future<void> _checkCriticalPermissionsRealtime({
    bool showPopupIfMissing = false,
  }) async {
    if (!mounted) return;
    final status = await PowerOptimizationService.instance
        .checkCriticalPermissionsStatus();
    final hasDismissed = await PowerOptimizationService.instance
        .hasUserDismissedOnboarding();
    if (!mounted) return;
    setState(() {
      _permissionStatus = status;
      _hasUserCompletedOrDismissedOnboarding = hasDismissed;
    });

    if (status.hasMissingCriticalPermissions &&
        showPopupIfMissing &&
        !_isPermissionDialogShowing &&
        !_isRequestingPermissions) {
      if (status.onlyBatteryOptimizationMissing) {
        await PowerOptimizationService.instance
            .requestIgnoreBatteryOptimizations();
        return;
      }
      if (status.onlyNotificationsMissing) {
        final canDirect = await PowerOptimizationService.instance
            .canRequestDirectNotificationPermission();
        if (canDirect) {
          await PowerOptimizationService.instance
              .requestNotificationPermission();
          return;
        }
      }
      if (_hasItemsToShow(status)) {
        await _showPermissionGuideDialog(status);
      }
    }
  }

  Future<void> _handleFixPermission(CriticalPermissionsStatus status) async {
    // 1. Nếu chỉ thiếu pin: bung popup 1-chạm mặc định của Android
    if (status.onlyBatteryOptimizationMissing) {
      await PowerOptimizationService.instance
          .requestIgnoreBatteryOptimizations();
      await _checkCriticalPermissionsRealtime(showPopupIfMissing: false);
      return;
    }
    // 2. Nếu chỉ thiếu thông báo: bung popup mặc định của điện thoại nếu có thể
    if (status.onlyNotificationsMissing) {
      final canDirect = await PowerOptimizationService.instance
          .canRequestDirectNotificationPermission();
      if (canDirect) {
        await PowerOptimizationService.instance.requestNotificationPermission();
        await _checkCriticalPermissionsRealtime(showPopupIfMissing: false);
        return;
      }
    }
    // 3. Nếu cần mở Cài đặt (Samsung, Xiaomi, Thông báo bị chặn): mở hướng dẫn đơn giản
    await _showPermissionGuideDialog(status);
  }

  bool get _shouldShowStickyPermissionBanner {
    final status = _permissionStatus;
    if (status == null || !status.hasMissingCriticalPermissions) {
      return false;
    }
    if (!_hasUserCompletedOrDismissedOnboarding) {
      return false;
    }
    return true;
  }

  Widget _buildStickyPermissionWarning() {
    if (!_shouldShowStickyPermissionBanner) {
      return const SizedBox.shrink();
    }
    final status = _permissionStatus!;

    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.primaryWarningMessage ?? 'Quyền chạy ngầm đang bị tắt.',
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
            onPressed: () => _handleFixPermission(status),
            child: const Text(
              'CÀI ĐẶT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShakeController {
  void Function()? _shakeAction;
  void shake() => _shakeAction?.call();
}

class _ShakeWidget extends StatefulWidget {
  final Widget child;
  final _ShakeController controller;

  const _ShakeWidget({required this.child, required this.controller});

  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    widget.controller._shakeAction = _shake;
  }

  void _shake() {
    if (mounted) {
      _animCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        final progress = _animCtrl.value;
        final offset = sin(progress * pi * 6) * (8.0 * (1.0 - progress));
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: widget.child,
    );
  }
}

class _SimplePermissionGuideDialog extends StatefulWidget {
  final CriticalPermissionsStatus initialStatus;
  final bool isFirstLaunch;

  const _SimplePermissionGuideDialog({
    required this.initialStatus,
    this.isFirstLaunch = false,
  });

  @override
  State<_SimplePermissionGuideDialog> createState() =>
      _SimplePermissionGuideDialogState();
}

class _SimplePermissionGuideDialogState
    extends State<_SimplePermissionGuideDialog>
    with WidgetsBindingObserver {
  late CriticalPermissionsStatus _status;
  final _backgroundDataShakeCtrl = _ShakeController();
  final _notificationShakeCtrl = _ShakeController();
  final _batteryShakeCtrl = _ShakeController();

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final updated = await PowerOptimizationService.instance
        .checkCriticalPermissionsStatus();
    if (!mounted) return;
    setState(() => _status = updated);
    // Giữ nguyên dialog, người dùng chủ động bấm Đóng
  }

  void _handleClose() {
    bool canClose = true;

    if (_status.backgroundDataRestricted) {
      _backgroundDataShakeCtrl.shake();
      canClose = false;
    }
    if (!_status.notificationsEnabled) {
      _notificationShakeCtrl.shake();
      canClose = false;
    }
    if (!_status.batteryOptimizationIgnored &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      _batteryShakeCtrl.shake();
      canClose = false;
    }

    if (canClose) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mfg = _status.manufacturer.toLowerCase();
    final isSamsung = mfg.contains('samsung');
    final isChineseOem =
        mfg.contains('xiaomi') ||
        mfg.contains('redmi') ||
        mfg.contains('poco') ||
        mfg.contains('oppo') ||
        mfg.contains('realme') ||
        mfg.contains('vivo') ||
        mfg.contains('huawei') ||
        mfg.contains('honor');

    final items = <Widget>[];

    // 1. Quyền dữ liệu nền & Tiết kiệm pin
    // Hiển thị nếu:
    // a) Đang bị Android hạn chế dữ liệu nền (status.backgroundDataRestricted == true)
    // b) HOẶC là lần đầu cài đặt (widget.isFirstLaunch == true) trên Android để hướng dẫn bật phòng ngừa
    if (_status.backgroundDataRestricted ||
        (widget.isFirstLaunch &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android)) {
      items.add(
        _ShakeWidget(
          controller: _backgroundDataShakeCtrl,
          child: _buildItem(
            title: 'Quyền dữ liệu nền & Tiết kiệm pin',
            badgeText: _status.backgroundDataRestricted
                ? 'Bắt buộc'
                : 'Khuyến nghị',
            badgeColor: _status.backgroundDataRestricted
                ? const Color(0xFFDC2626)
                : const Color(0xFFD97706),
            description: 'Bật "Cho phép dùng dữ liệu nền" và "Cho phép dùng dữ liệu khi bật Tiết kiệm dữ liệu / Tiết kiệm pin" để nhận tín hiệu cấp cứu.',
            buttonText: 'Mở cài đặt',
            onPressed: () =>
                PowerOptimizationService.instance.openBackgroundDataSettings(),
          ),
        ),
      );
    }

    // 2. Quyền thông báo (Quét được - Bắt buộc nếu chưa cấp)
    if (!_status.notificationsEnabled) {
      items.add(
        _ShakeWidget(
          controller: _notificationShakeCtrl,
          child: _buildItem(
            title: 'Quyền thông báo',
            badgeText: 'Bắt buộc',
            badgeColor: const Color(0xFFDC2626),
            description:
                'Cần bật thông báo để chuông cấp cứu kêu khi có sự cố.',
            buttonText: 'Mở cài đặt',
            onPressed: () =>
                PowerOptimizationService.instance.openNotificationSettings(),
          ),
        ),
      );
    }

    // 3. Quyền chạy ngầm pin chuẩn (Quét được - Bắt buộc nếu chưa cấp)
    if (!_status.batteryOptimizationIgnored &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      items.add(
        _ShakeWidget(
          controller: _batteryShakeCtrl,
          child: _buildItem(
            title: 'Quyền chạy ngầm (Pin)',
            badgeText: 'Bắt buộc',
            badgeColor: const Color(0xFFDC2626),
            description: 'Chọn "Không hạn chế" để ứng dụng không bị đóng băng khi tắt màn hình.',
            buttonText: 'Cho phép',
            onPressed: () => PowerOptimizationService.instance
                .requestIgnoreBatteryOptimizations(),
          ),
        ),
      );
    }

    // 4. Quyền của hãng: Ứng dụng không bao giờ ngủ (Samsung) / Tự khởi chạy (Xiaomi...) - TÙY CHỌN
    if (isSamsung) {
      items.add(
        _buildItem(
          title: 'Ứng dụng không bao giờ ngủ (Samsung)',
          badgeText: 'Tùy chọn',
          badgeColor: const Color(0xFF4A3020),
          description: 'Cài đặt > Pin > Giới hạn sử dụng dưới nền > Ứng dụng không bao giờ ngủ > Thêm CareAI.',
          reason: 'Lý do: Giúp chuông báo cấp cứu không bị hãng điện thoại tự động tắt khi không mở ứng dụng trong nhiều ngày.',
          buttonText: 'Mở cài đặt',
          onPressed: () =>
              PowerOptimizationService.instance.openAutostartSettings(),
        ),
      );
    } else if (isChineseOem) {
      items.add(
        _buildItem(
          title: 'Tự khởi chạy (${_status.manufacturer})',
          badgeText: 'Tùy chọn',
          badgeColor: const Color(0xFF4A3020),
          description:
              'Cài đặt > Quản lý ứng dụng > Tự khởi chạy > Bật CareAI.',
          reason: 'Lý do: Giúp hệ thống duy trì kết nối cứu hộ và không tắt chuông báo động khi bạn vuốt dọn dẹp app.',
          buttonText: 'Mở cài đặt',
          onPressed: () =>
              PowerOptimizationService.instance.openAutostartSettings(),
        ),
      );
    }

    return AlertDialog(
      title: const Text(
        'Cài đặt quyền ứng dụng',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A3020),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: _handleClose,
            child: const Text(
              'Đóng',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildItem({
    required String title,
    required String badgeText,
    required Color badgeColor,
    required String description,
    String? reason,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: badgeColor.withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: Color(0xFF4A3020)),
          ),
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(
              reason,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFF7D7168),
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onPressed, child: Text(buttonText)),
        ],
      ),
    );
  }
}
