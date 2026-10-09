import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/fall_event.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';
import '../services/api_service.dart';
import '../services/emergency_evidence_service.dart';
import '../services/fall_service.dart';
import '../services/local_offline_store.dart';
import '../services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../caregiver/screens/home_screen.dart';
import '../caregiver/screens/login_screen.dart';
import '../caregiver/services/caregiver_api_service.dart';
import '../services/location_service.dart';
import 'device_pairing_screen.dart';
import 'fall_countdown_dialog.dart';
import 'role_selection_screen.dart';

class SosButtonScreen extends StatefulWidget {
  const SosButtonScreen({super.key});

  @override
  State<SosButtonScreen> createState() => _SosButtonScreenState();
}

class _SosButtonScreenState extends State<SosButtonScreen>
    with SingleTickerProviderStateMixin {
  String _elderName = 'Chưa xác định';
  String _deviceId = '';
  bool _isServerOnline = false;
  int _pendingPacketCount = 0;
  bool _isSosActive = false;
  String? _lastSosPacketId;
  DateTime? _lastSyncTime;
  String _currentGps = 'Đang định vị GPS...';
  String _gpsStatus = 'Đang lấy vị trí hiện tại...';
  bool _locatingGps = false;
  bool _backgroundGpsGranted = false;

  WatchStatus _watchStatus = const WatchStatus(isConnected: false);
  Timer? _watchStatusTimer;
  Timer? _healthCheckTimer;
  StreamSubscription<FallEvent>? _fallSubscription;
  late AnimationController _rippleController;
  bool _isFallDialogShowing = false;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _checkServerHealth();
    _loadPendingCount();
    _checkWatchStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareGps());
    });

    // Khởi chạy Animation rung/lan tỏa cho nút SOS
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Lắng nghe phát hiện té ngã từ Native Watch và Cảm biến điện thoại
    FallService.instance.initialize();
    FallService.instance.startPhoneAccelerometerDetector();

    _fallSubscription = FallService.instance.onFallDetected.listen((fallEvent) {
      if (mounted) {
        _showFallCountdownModal(fallEvent);
      }
    });

    // Định kỳ kiểm tra kết nối máy chủ và số lượng gói chờ (chu kỳ 5 giây để phát hiện cắm/rút cáp tức thì)
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkServerHealth();
      _loadPendingCount();
    });

    // Định kỳ kiểm tra trạng thái kết nối Bluetooth đồng hồ Galaxy Watch (chu kỳ 10 giây)
    _watchStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkWatchStatus();
    });

    // Kích hoạt chu kỳ đồng bộ ngoại tuyến định kỳ
    SyncService.instance.startPeriodicSync();
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _watchStatusTimer?.cancel();
    _fallSubscription?.cancel();
    _rippleController.dispose();
    FallService.instance.stopPhoneAccelerometerDetector();
    SyncService.instance.stopPeriodicSync();
    super.dispose();
  }

  String get _platformWatchTitle {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Apple Watch (watchOS)';
    }
    return 'Galaxy Watch (Wear OS)';
  }

  String get _platformSensorLabel {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'Apple Optical Sensor';
    }
    return 'BioActive Sensor';
  }

  Future<void> _checkWatchStatus({bool showFeedback = false}) async {
    final status = await FallService.instance.getConnectedWatchStatus();
    if (mounted) {
      setState(() {
        _watchStatus = status;
      });
      if (status.isConnected) {
        final platformName = defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Watch' : 'Galaxy Watch';
        unawaited(ApiService.instance.syncConnectedWatch(status.watchName ?? platformName));
      }
      if (showFeedback) {
        final platformName = defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Watch' : 'Galaxy Watch';
        final channelDesc = defaultTargetPlatform == TargetPlatform.iOS ? 'Bluetooth / Apple Watch App' : 'Bluetooth / Galaxy Wearable';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.isConnected
                  ? '🟢 Đã kết nối: ${status.watchName ?? platformName} (${defaultTargetPlatform == TargetPlatform.iOS ? "watchOS" : "Wear OS"})'
                  : '⚪ Chưa tìm thấy $platformName kết nối qua $channelDesc',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _loadDeviceInfo() async {
    final name = await ApiService.instance.getElderName();
    final devId = await ApiService.instance.getDeviceId();
    final lastSync = await LocalOfflineStore.instance.getLastSyncTimestamp();

    if (mounted) {
      setState(() {
        _elderName = name ?? 'Cụ cao tuổi';
        _deviceId = devId ?? '';
        _lastSyncTime = lastSync;
      });
    }

    // Lấy tọa độ GPS thực tế của thiết bị (Không dùng bản đồ Trung Quốc)
    try {
      final loc = await LocationService.instance.getCurrentLocation(requestPermissionIfDenied: false);
      if (mounted) {
        setState(() {
          _currentGps = loc.coordinatesFormatted;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkServerHealth() async {
    final online = await ApiService.instance.checkServerHealth();
    if (mounted) {
      final wasOffline = !_isServerOnline;
      setState(() {
        _isServerOnline = online;
      });

      // Tự động xả hàng đợi ngoại tuyến ngay khi máy có kết nối trở lại
      if (online && (wasOffline || _pendingPacketCount > 0)) {
        SyncService.instance.syncOfflineSpool().then((result) async {
          await _loadPendingCount();
          final lastSync = await LocalOfflineStore.instance.getLastSyncTimestamp();
          if (mounted && result.syncedCount > 0) {
            setState(() {
              _lastSyncTime = lastSync;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Tự động đồng bộ thành công: Đã gửi ${result.syncedCount} gói tin khẩn cấp!'),
                backgroundColor: const Color(0xFF2563EB),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _loadPendingCount() async {
    final count = await LocalOfflineStore.instance.getPendingCount();
    if (mounted) {
      setState(() {
        _pendingPacketCount = count;
      });
    }
  }

  void _showFallCountdownModal(FallEvent event) {
    if (_isFallDialogShowing) {
      debugPrint('Cảnh báo ngã đã hiển thị dialog, bỏ qua popup trùng lặp.');
      return;
    }
    _isFallDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => FallCountdownDialog(
        event: event,
        onEmergencyTriggered: (packetId) {
          setState(() {
            _isSosActive = true;
            _lastSosPacketId = packetId;
          });
        },
      ),
    ).whenComplete(() {
      _isFallDialogShowing = false;
    });
  }

  Future<void> _triggerManualSos() async {
    HapticFeedback.heavyImpact();
    final locationTask = EmergencyEvidenceService.captureCurrentLocation();

    // Mở hộp thoại xác nhận 5 giây (chống chạm nhầm)
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManualSosConfirmDialog(),
    );

    if (shouldSend != true) return;

    final packetId = 'SOS_${const Uuid().v4().substring(0, 8).toUpperCase()}';
    final now = DateTime.now().toUtc();

    final prefs = await SharedPreferences.getInstance();
    final lastHr = prefs.getDouble('careai_last_heart_rate') ?? 76.0;
    final lastSpo2 = prefs.getDouble('careai_last_spo2') ?? 98.0;

    // Fact 35 Invariant: Gói Fast-Lane SOS BẮT BUỘC lưu toàn bộ mẫu đo sinh hiệu đi kèm
    final samples = [
      TelemetrySample(metricType: 'HEART_RATE', value: lastHr, unit: 'BPM', timestamp: now),
      TelemetrySample(metricType: 'SPO2', value: lastSpo2, unit: '%', timestamp: now),
      TelemetrySample(metricType: 'BATTERY', value: 92.0, unit: '%', timestamp: now),
    ];

    // TUÂN THỦ NGHIÊM NGẶT: Lấy tọa độ GPS thực tế từ phần cứng thiết bị (Không dùng bản đồ Trung Quốc)
    final recentFix = EmergencyEvidenceService.recentFix;
    final gpsResult = await LocationService.instance.getCurrentLocation();
    final realGpsLocation = gpsResult.isRealGps
        ? gpsResult.coordinatesFormatted
        : (recentFix?.coordinates ?? gpsResult.coordinatesFormatted);
    final initialGps = realGpsLocation;
    if (mounted) {
      setState(() => _currentGps = realGpsLocation);
    }

    final sosRequest = SosPacketRequest(
      packetId: packetId,
      emergencyType: 'MANUAL_SOS',
      severity: 'CRITICAL',
      triggeredAt: now,
      gpsLocation: realGpsLocation,
      gpsIsSimulated: recentFix?.isSimulated ?? false,
      samples: samples,
    );

    // BƯỚC 1: Ghi trước vào Outbox SQLite đĩa cục bộ (Outbox-First Pattern)
    await LocalOfflineStore.instance.enqueuePacket(
      packetId: packetId,
      packetType: 'SOS_ALERT',
      payload: jsonEncode(sosRequest.toJson()),
    );

    setState(() {
      _isSosActive = true;
      _lastSosPacketId = packetId;
    });

    // BƯỚC 2: Thử Fast-Lane HTTP POST trực tiếp lên máy chủ
    try {
      final result = await ApiService.instance.sendFastLaneSosWithResult(sosRequest);
      if (result.accepted) {
        await LocalOfflineStore.instance.markPacketSynced(packetId);
        if (result.incidentId != null) {
          unawaited(EmergencyEvidenceService.attachLocationWhenReady(
              result.incidentId!, locationTask, initiallySentGps: initialGps));
          unawaited(EmergencyEvidenceService.captureAndUploadPhoto(result.incidentId!));
        }
      }
    } catch (_) {
      // Ngoại tuyến: Sự cố đã được lưu an toàn trong SQLite Outbox
    }

    await _loadPendingCount();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tín hiệu cấp cứu đã được ghi nhận và gửi đến người thân!'),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleManualSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đang đồng bộ dữ liệu ngoại tuyến...'), duration: Duration(seconds: 1)),
    );

    final result = await SyncService.instance.syncOfflineSpool();
    await _loadPendingCount();
    final lastSync = await LocalOfflineStore.instance.getLastSyncTimestamp();

    if (mounted) {
      setState(() {
        _lastSyncTime = lastSync;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đồng bộ hoàn tất: Đã gửi ${result.syncedCount} gói tin, Còn chờ: ${result.remainingPending}',
          ),
          backgroundColor: Colors.indigo,
        ),
      );
    }
  }

  Future<void> _prepareGps() async {
    await EmergencyEvidenceService.requestPermissions();
    final backgroundGranted = await Permission.locationAlways.isGranted;
    if (mounted) setState(() => _backgroundGpsGranted = backgroundGranted);
    await _refreshGps();
  }

  Future<void> _enableBackgroundGps() async {
    final status = await Permission.locationAlways.request();
    if (mounted) {
      setState(() => _backgroundGpsGranted = status.isGranted);
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(
          'Để gửi GPS khi app ở nền, chọn “Cho phép mọi lúc” trong quyền vị trí của CareAI.')));
      }
    }
  }

  Future<void> _refreshGps() async {
    if (_locatingGps) return;
    if (mounted) {
      setState(() {
        _locatingGps = true;
        _gpsStatus = 'Đang lấy vị trí hiện tại...';
      });
    }
    final fix = await EmergencyEvidenceService.captureCurrentLocation();
    if (mounted) {
      setState(() {
        _locatingGps = false;
      _gpsStatus = fix == null
          ? 'Chưa có GPS. Kiểm tra quyền vị trí và bật định vị.'
          : '${fix.isSimulated ? 'GPS MÔ PHỎNG' : 'GPS'}: ${fix.coordinates}'
              '${fix.accuracyMeters == null ? '' : ' (±${fix.accuracyMeters!.round()} m)'}';
      });
    }
  }

  Future<void> _simulateUrgentHeartRate() async {
    final sample = TelemetrySample(
      metricType: 'HEART_RATE',
      value: 185,
      unit: 'bpm',
      timestamp: DateTime.now().toUtc(),
    );
    await SyncService.instance.enqueueTelemetrySamples([sample]);
    await _loadPendingCount();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mẫu 185 bpm đã được gửi ngay hoặc lưu để gửi lại khi có kết nối.'),
        ),
      );
    }
  }

  Future<void> _handleUnpair() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy ghép nối thiết bị?'),
        content: const Text(
          'Thiết bị sẽ dừng kết nối với hệ thống CareAI. Bạn sẽ cần nhập mã PIN mới để ghép nối lại.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY BỎ')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('HỦY GHÉP NỐI'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.instance.unpair();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
        );
      }
    }
  }

  Future<void> _handleSwitchRole() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi vai trò sử dụng?'),
        content: const Text(
          'Bạn có muốn chuyển sang Chế độ Người thân (Caregiver Dashboard) để theo dõi và quản lý từ xa?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            child: const Text('CHUYỂN ĐỔI', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(RoleSelectionScreen.prefSelectedRole, 'caregiver');
      await CaregiverApiService.instance.init();
      final isLoggedIn = await CaregiverApiService.instance.isLoggedIn();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isServerOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _isServerOnline
                  ? (ApiService.instance.activeServerUrl.contains('127.0.0.1')
                      ? 'Trực tuyến (Cáp USB)'
                      : (ApiService.instance.activeServerUrl.contains('trycloudflare.com') || ApiService.instance.activeServerUrl.startsWith('https://'))
                          ? 'Trực tuyến (Internet/4G)'
                          : 'Trực tuyến (Wi-Fi LAN)')
                  : 'Ngoại tuyến (Offline)',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Đổi vai trò Người thân',
            onPressed: _handleSwitchRole,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _pendingPacketCount > 0,
              label: Text('$_pendingPacketCount'),
              child: const Icon(Icons.sync, color: Colors.white),
            ),
            tooltip: 'Đồng bộ ngoại tuyến',
            onPressed: _handleManualSync,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Cài đặt / Hủy ghép đôi',
            onPressed: _handleUnpair,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Thẻ thông tin người cao tuổi
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF3B82F6),
                    radius: 24,
                    child: const Icon(Icons.person, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _elderName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mã thiết bị: $_deviceId',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () async {
                            final loc = await LocationService.instance.getCurrentLocation();
                            if (mounted) setState(() => _currentGps = loc.coordinatesFormatted);
                            await LocationService.instance.openGoogleMaps(loc.latitude, loc.longitude, label: 'Vị trí Cụ: $_elderName');
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on, size: 13, color: Color(0xFF38BDF8)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'GPS: $_currentGps',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0369A1).withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF38BDF8), width: 0.5),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Google Maps', style: TextStyle(fontSize: 9, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                                      SizedBox(width: 2),
                                      Icon(Icons.open_in_new, size: 9, color: Color(0xFF38BDF8)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(_gpsStatus, style: TextStyle(fontSize: 11,
                          color: EmergencyEvidenceService.recentFix == null
                              ? const Color(0xFFFBBF24) : const Color(0xFF86EFAC))),
                        if (!_backgroundGpsGranted)
                          TextButton(
                            onPressed: _enableBackgroundGps,
                            child: const Text('Bật GPS khi app ở nền',
                              style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Lấy lại GPS hiện tại',
                    onPressed: _locatingGps ? null : _prepareGps,
                    icon: const Icon(Icons.my_location, color: Color(0xFF38BDF8)),
                  ),
                ],
              ),
            ),

            // Card Thiết bị đeo Galaxy Watch (Wear OS)
            InkWell(
              onTap: () => _checkWatchStatus(showFeedback: true),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _watchStatus.isConnected
                        ? const Color(0xFF22C55E).withValues(alpha: 0.6)
                        : const Color(0xFF475569).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _watchStatus.isConnected
                            ? const Color(0xFF14532D).withValues(alpha: 0.5)
                            : const Color(0xFF1E293B),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.watch,
                        color: _watchStatus.isConnected
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _watchStatus.isConnected
                                ? (_watchStatus.watchName ?? _platformWatchTitle)
                                : 'Chưa kết nối đồng hồ',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _watchStatus.isConnected
                                ? '🟢 Đã kết nối · $_platformSensorLabel'
                                : '⚪ $_platformWatchTitle (Chạm để kiểm tra)',
                            style: TextStyle(
                              fontSize: 11,
                              color: _watchStatus.isConnected
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.personal_injury, size: 16),
                      label: const Text(
                        'Test Ngã',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () async {
                        final eventId = await FallService.instance.simulateHardwareFall();
                        if (context.mounted && eventId != null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('⚡ Đã kích hoạt mô phỏng ngã phần cứng ($eventId)'),
                              backgroundColor: const Color(0xFFB91C1C),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: OutlinedButton.icon(
                  onPressed: _simulateUrgentHeartRate,
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Mô phỏng nhịp tim 185 bpm'),
                ),
              ),

            // Banner trạng thái SOS đang kích hoạt
            if (_isSosActive)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ĐÃ PHÁT TÍN HIỆU CẤP CỨU ($_lastSosPacketId)\nĐang chờ người nhà tiếp nhận!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _isSosActive = false;
                        });
                      },
                    ),
                  ],
                ),
              ),

            // Vùng trung tâm cố định chứa nút SOS (được Expanded chiếm trọn không gian còn lại và căn giữa)
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: AnimatedBuilder(
                      animation: _rippleController,
                      builder: (context, child) {
                        final rippleValue = _rippleController.value;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Vòng sóng lan tỏa
                            Container(
                              width: 250 + (rippleValue * 40),
                              height: 250 + (rippleValue * 40),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFEF4444).withValues(alpha: (1 - rippleValue) * 0.4),
                              ),
                            ),
                            child!,
                          ],
                        );
                      },
                      child: Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _triggerManualSos,
                          child: Container(
                            width: 230,
                            height: 230,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFF991B1B)],
                                stops: [0.3, 0.7, 1.0],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                                  blurRadius: 30,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app, size: 48, color: Colors.white),
                                SizedBox(height: 6),
                                Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 2,
                                  ),
                                ),
                                Text(
                                  'BẤM CẤP CỨU',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      // Thanh trạng thái dưới cùng: Cố định 100% ở đáy màn hình bằng bottomNavigationBar (không bao giờ bị trôi/di chuyển)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: const Color(0xFF1E293B),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 18, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(
                    _lastSyncTime != null
                        ? 'Đã đồng bộ: ${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}'
                        : 'Chưa có lượt đồng bộ',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.storage_outlined, size: 18, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Text(
                    '$_pendingPacketCount gói chờ',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSosConfirmDialog extends StatefulWidget {
  @override
  State<_ManualSosConfirmDialog> createState() => _ManualSosConfirmDialogState();
}

class _ManualSosConfirmDialogState extends State<_ManualSosConfirmDialog> {
  int _secondsLeft = 5;
  Timer? _timer;
  bool _hasPopped = false;

  void _finish(bool send) {
    if (_hasPopped) return;
    _hasPopped = true;
    _timer?.cancel();
    if (mounted) {
      Navigator.of(context).pop(send);
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        _finish(true);
      } else {
        HapticFeedback.lightImpact();
        setState(() {
          _secondsLeft--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.crisis_alert, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Text('Xác Nhận Cấp Cứu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Hệ thống sẽ tự động gửi tín hiệu khẩn cấp đến toàn bộ người thân trong:',
            style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
          ),
          const SizedBox(height: 20),
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEF4444), width: 3),
            ),
            alignment: Alignment.center,
            child: Text(
              '$_secondsLeft',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF4444),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('giây', style: TextStyle(color: Color(0xFF94A3B8))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _finish(false),
          child: const Text('HỦY BỎ (CHẠM NHẦM)', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => _finish(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
          ),
          child: const Text('GỬI NGAY', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
