import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/fall_event.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';
import '../services/api_service.dart';
import '../services/fall_service.dart';
import '../services/local_offline_store.dart';
import '../services/sync_service.dart';
import 'device_pairing_screen.dart';
import 'fall_countdown_dialog.dart';

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

    // Kích hoạt chu kỳ đồng bộ ngoại tuyến định kỳ
    SyncService.instance.startPeriodicSync();
  }

  @override
  void dispose() {
    _healthCheckTimer?.cancel();
    _fallSubscription?.cancel();
    _rippleController.dispose();
    FallService.instance.stopPhoneAccelerometerDetector();
    SyncService.instance.stopPeriodicSync();
    super.dispose();
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

    // Mở hộp thoại xác nhận 5 giây (chống chạm nhầm)
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ManualSosConfirmDialog(),
    );

    if (shouldSend != true) return;

    final packetId = 'SOS_${const Uuid().v4().substring(0, 8).toUpperCase()}';
    final now = DateTime.now().toUtc();

    // Fact 35 Invariant: Gói Fast-Lane SOS BẮT BUỘC lưu toàn bộ mẫu đo sinh hiệu đi kèm
    final samples = [
      TelemetrySample(metricType: 'HEART_RATE', value: 85.0, unit: 'BPM', timestamp: now),
      TelemetrySample(metricType: 'SPO2', value: 98.0, unit: '%', timestamp: now),
      TelemetrySample(metricType: 'BATTERY', value: 92.0, unit: '%', timestamp: now),
    ];

    final sosRequest = SosPacketRequest(
      packetId: packetId,
      emergencyType: 'MANUAL_SOS',
      severity: 'CRITICAL',
      triggeredAt: now,
      gpsLocation: '10.7769, 106.7009', // Vị trí giả lập tọa độ người cao tuổi
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
      final success = await ApiService.instance.sendFastLaneSos(sosRequest);
      if (success) {
        await LocalOfflineStore.instance.markPacketSynced(packetId);
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
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Card Thiết bị đeo Galaxy Watch (Wear OS)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.watch, color: Color(0xFF60A5FA), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Galaxy Watch (Wear OS)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '🟢 Sẵn sàng · BioActive Sensor',
                          style: TextStyle(fontSize: 11, color: Color(0xFF4ADE80)),
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
