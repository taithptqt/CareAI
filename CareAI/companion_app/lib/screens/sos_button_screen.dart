import 'dart:async';
import 'dart:convert';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  String? _lastPairedWatchName;
  Timer? _watchStatusTimer;
  Timer? _watchDisconnectDebounceTimer;
  bool _isDebouncingDisconnect = false;
  static const Duration _kWatchDisconnectDebounce = Duration(minutes: 3);
  Timer? _healthCheckTimer;
  StreamSubscription<FallEvent>? _fallSubscription;
  StreamSubscription<WatchStatus>? _watchStatusSubscription;
  late AnimationController _rippleController;
  bool _isFallDialogShowing = false;

  int _secretTapCount = 0;
  DateTime _lastSecretTap = DateTime(0);

  void _handleSecretTitleTap() {
    final now = DateTime.now();
    if (now.difference(_lastSecretTap).inMilliseconds < 2500) {
      _secretTapCount++;
      if (_secretTapCount >= 5) {
        _secretTapCount = 0;
        HapticFeedback.heavyImpact();
        _showDiagnosticTestLabSheet(context);
      }
    } else {
      _secretTapCount = 1;
    }
    _lastSecretTap = now;
  }

  @override
  void initState() {
    super.initState();
    // Khởi tạo FallService và lắng nghe sự kiện Native trước khi truy vấn trạng thái
    FallService.instance.initialize();
    FallService.instance.startPhoneAccelerometerDetector();

    _fallSubscription = FallService.instance.onFallDetected.listen((fallEvent) {
      if (mounted) {
        _showFallCountdownModal(fallEvent);
      }
    });

    // Lắng nghe sự kiện kết nối/ngắt kết nối đồng hồ thời gian thực (Event-Driven 0.1 giây từ Native Android/iOS)
    _watchStatusSubscription = FallService.instance.onWatchConnectionChanged.listen((status) {
      if (mounted) {
        _applyWatchStatus(status);
      }
    });

    WidgetsBinding.instance.addObserver(this);
    _initLastPairedWatchName();
    _loadDeviceInfo();
    _checkServerHealth();
    _loadPendingCount();
    _checkWatchStatus();
    // Thử lại sau 1.5 giây để đón nhận WCSession (iOS) hoặc Wearable API kích hoạt nền
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && !_watchStatus.isConnected) {
        _checkWatchStatus();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_prepareGps());
    });

    // Khởi chạy Animation rung/lan tỏa cho nút SOS
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Định kỳ kiểm tra kết nối máy chủ và số lượng gói chờ (chu kỳ 5 giây để phát hiện cắm/rút cáp tức thì)
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkServerHealth();
      _loadPendingCount();
    });

    // Fallback dự phòng kiểm tra trạng thái Bluetooth đồng hồ (chu kỳ giãn 60 giây để tiết kiệm pin tối đa nhờ Event-Driven)
    _watchStatusTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkWatchStatus();
    });

    // Kích hoạt chu kỳ đồng bộ ngoại tuyến định kỳ
    SyncService.instance.startPeriodicSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkWatchStatus());
      unawaited(_checkServerHealth());
      unawaited(_loadPendingCount());
    }
  }

  Future<void> _openBluetoothSettings() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        const intent = AndroidIntent(
          action: 'android.settings.BLUETOOTH_SETTINGS',
        );
        await intent.launch();
        return;
      } catch (e) {
        debugPrint('[SosButtonScreen] Lỗi mở cài đặt Bluetooth Android: $e');
      }
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final uri = Uri.parse('App-Prefs:Bluetooth');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (e) {
        debugPrint('[SosButtonScreen] Lỗi mở App-Prefs:Bluetooth iOS: $e');
      }
    }
    await openAppSettings();
  }

  Future<void> _initLastPairedWatchName() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('last_paired_watch_name');
    if (mounted && saved != null && saved.isNotEmpty) {
      setState(() {
        _lastPairedWatchName = saved;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthCheckTimer?.cancel();
    _watchStatusTimer?.cancel();
    _watchDisconnectDebounceTimer?.cancel();
    _fallSubscription?.cancel();
    _watchStatusSubscription?.cancel();
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
      return 'Cảm biến quang học PPG / ECG';
    }
    return 'Cảm biến BioActive / PPG';
  }

  Future<void> _checkWatchStatus({bool showFeedback = false}) async {
    if (showFeedback && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('🔍 Đang kiểm tra kết nối đồng hồ...'),
            ],
          ),
          duration: Duration(milliseconds: 1200),
        ),
      );
    }
    final status = await FallService.instance.getConnectedWatchStatus();
    if (mounted) {
      await _applyWatchStatus(status, showFeedback: showFeedback);
    }
  }

  Future<void> _applyWatchStatus(WatchStatus status, {bool showFeedback = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedWatchName = prefs.getString('last_paired_watch_name');

    if (mounted) {
      if (status.isConnected) {
        // Hủy bộ đếm hoãn ngắt kết nối nếu đang đếm (đồng hồ đã kết nối lại an toàn)
        _watchDisconnectDebounceTimer?.cancel();
        _watchDisconnectDebounceTimer = null;
        setState(() {
          _watchStatus = status;
          _isDebouncingDisconnect = false;
          if (savedWatchName != null && savedWatchName.isNotEmpty) {
            _lastPairedWatchName = savedWatchName;
          }
        });

        final platformName = defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Watch' : 'Galaxy Watch';
        final effectiveName = status.watchName ?? platformName;
        _lastPairedWatchName = effectiveName;
        await prefs.setString('last_paired_watch_name', effectiveName);

        unawaited(ApiService.instance.syncConnectedWatch(
          effectiveName,
          isConnected: true,
          isWorn: status.isWorn,
          isCharging: status.isCharging,
          batteryLevel: status.batteryLevel,
        ));
        unawaited(() async {
          final serverUrl = await ApiService.instance.getServerUrl();
          final devId = await ApiService.instance.getDeviceId();
          final devToken = await ApiService.instance.getDeviceToken();
          if (devId != null && devToken != null && devId.isNotEmpty && devToken.isNotEmpty) {
            await FallService.instance.syncWatchCredentials(
              backendUrl: serverUrl,
              deviceId: devId,
              deviceToken: devToken,
              elderName: _elderName,
            );
          }
        }());
      } else {
        // Đang không kết nối:
        if (status.reason == 'BLUETOOTH_OFF') {
          // Trường hợp A: Tắt Bluetooth chủ động trên điện thoại -> Báo Server ngay lập tức (0.1 giây)
          _watchDisconnectDebounceTimer?.cancel();
          _watchDisconnectDebounceTimer = null;
          setState(() {
            _watchStatus = status;
            _isDebouncingDisconnect = false;
            if (savedWatchName != null && savedWatchName.isNotEmpty) {
              _lastPairedWatchName = savedWatchName;
            }
          });
          if (_lastPairedWatchName != null && _lastPairedWatchName!.isNotEmpty) {
            unawaited(ApiService.instance.syncConnectedWatch(
              _lastPairedWatchName!,
              isConnected: false,
              disconnectReason: 'BLUETOOTH_OFF',
            ));
          }
        } else {
          // Trường hợp B: Mất sóng BLE tạm thời do đi xa / qua tường -> Giữ trạng thái debounce 3 phút chống báo động giả
          if (_watchDisconnectDebounceTimer == null || !_watchDisconnectDebounceTimer!.isActive) {
            setState(() {
              _watchStatus = status;
              _isDebouncingDisconnect = true;
              if (savedWatchName != null && savedWatchName.isNotEmpty) {
                _lastPairedWatchName = savedWatchName;
              }
            });
            _watchDisconnectDebounceTimer = Timer(_kWatchDisconnectDebounce, () {
              if (mounted) {
                setState(() {
                  _isDebouncingDisconnect = false;
                });
                if (!_watchStatus.isConnected && _lastPairedWatchName != null && _lastPairedWatchName!.isNotEmpty) {
                  debugPrint('[SosButtonScreen] Đã quá 3 phút mất sóng BLE -> Xác nhận ngắt kết nối thật, thông báo lên máy chủ');
                  unawaited(ApiService.instance.syncConnectedWatch(
                    _lastPairedWatchName!,
                    isConnected: false,
                    disconnectReason: 'SIGNAL_LOST',
                  ));
                }
              }
            });
          } else {
            setState(() {
              _watchStatus = status;
              if (savedWatchName != null && savedWatchName.isNotEmpty) {
                _lastPairedWatchName = savedWatchName;
              }
            });
          }
        }
      }
      if (showFeedback && mounted) {
        final platformName = defaultTargetPlatform == TargetPlatform.iOS ? 'Apple Watch' : 'Galaxy Watch';
        final channelDesc = defaultTargetPlatform == TargetPlatform.iOS ? 'Bluetooth / Apple Watch App' : 'Bluetooth / Galaxy Wearable';
        final effectiveWatchName = status.watchName ?? _lastPairedWatchName ?? (status.isPaired ? platformName : null);
        String feedbackMsg;
        if (status.isConnected) {
          feedbackMsg = '🟢 Đã kết nối: ${effectiveWatchName ?? platformName} (${defaultTargetPlatform == TargetPlatform.iOS ? "watchOS" : "Wear OS"})';
        } else if (status.reason == 'BLUETOOTH_OFF') {
          feedbackMsg = '🔴 Bluetooth đang tắt${effectiveWatchName != null ? ": $effectiveWatchName" : ""} (Bật lại Bluetooth trên điện thoại)';
        } else if (effectiveWatchName != null) {
          feedbackMsg = '🔴 Mất tín hiệu: $effectiveWatchName (Kiểm tra khoảng cách/Pin đồng hồ)';
        } else {
          feedbackMsg = '⚪ Chưa phát hiện $platformName kết nối (Kiểm tra qua $channelDesc)';
        }

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(feedbackMsg),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadDeviceInfo() async {
    final name = await ApiService.instance.getElderName();
    final devId = await ApiService.instance.getDeviceId();
    final devToken = await ApiService.instance.getDeviceToken();
    final serverUrl = await ApiService.instance.getServerUrl();
    final lastSync = await LocalOfflineStore.instance.getLastSyncTimestamp();

    if (devId != null && devToken != null && devId.isNotEmpty && devToken.isNotEmpty) {
      unawaited(FallService.instance.syncWatchCredentials(
        backendUrl: serverUrl,
        deviceId: devId,
        deviceToken: devToken,
        elderName: name,
      ));
    }

    if (mounted) {
      setState(() {
        _elderName = name ?? 'Người cao tuổi';
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
    final lastHr = prefs.getDouble('careai_last_heart_rate');
    final lastSpo2 = prefs.getDouble('careai_last_spo2');

    // Fact 35 Invariant: Gói Fast-Lane SOS lưu toàn bộ mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
    final samples = <TelemetrySample>[];
    if (lastHr != null && lastHr > 0) {
      samples.add(TelemetrySample(metricType: 'HEART_RATE', value: lastHr, unit: 'BPM', timestamp: now));
    }
    if (lastSpo2 != null && lastSpo2 > 0) {
      samples.add(TelemetrySample(metricType: 'SPO2', value: lastSpo2, unit: '%', timestamp: now));
    }

    // TUÂN THỦ NGHIÊM NGẶT: Lấy tọa độ GPS thực tế từ phần cứng thiết bị (Không dùng bản đồ Trung Quốc)
    final recentFix = EmergencyEvidenceService.recentFix;
    final gpsResult = await LocationService.instance.getCurrentLocation();
    final realGpsLocation = gpsResult.isRealGps
        ? gpsResult.coordinatesFormatted
        : (recentFix != null && !recentFix.isSimulated ? recentFix.coordinates : null);
    if (mounted && realGpsLocation != null) {
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
              result.incidentId!, locationTask, initiallySentGps: realGpsLocation));
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
        const SnackBar(
          content: Text('Mẫu nhịp nhanh 185 bpm đã được gửi hoặc lưu vào hàng đợi.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _simulateHypoxiaSpO2() async {
    final sample = TelemetrySample(
      metricType: 'SPO2',
      value: 88.0,
      unit: '%',
      timestamp: DateTime.now().toUtc(),
    );
    await SyncService.instance.enqueueTelemetrySamples([sample]);
    await _loadPendingCount();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mẫu thiếu oxy SpO2 88% đã được gửi hoặc lưu vào hàng đợi.'),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );
    }
  }

  void _showDiagnosticTestLabSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.biotech_rounded, color: Color(0xFFF59E0B), size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phòng Thử Nghiệm Tín Hiệu',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Chuyên biệt cho kiểm thử lâm sàng & phần cứng',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFF334155), height: 1),
                      const SizedBox(height: 14),

                      // Section 1: Mô phỏng biến cố khẩn cấp
                      const Text(
                        'MÔ PHỎNG BIẾN CỐ KHẨN CẤP',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),

                      // Test Ngã Button
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        tileColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF7F1D1D)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.personal_injury, color: Color(0xFFEF4444), size: 22),
                        ),
                        title: const Text('Mô phỏng té ngã phần cứng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Kích hoạt chu trình đếm ngược 15s và còi SOS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
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
                          child: const Text('Kích hoạt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 2: Sinh hiệu lâm sàng
                      const Text(
                        'THỬ NGHIỆM SINH HIỆU LÂM SÀNG',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),

                      // Test Nhịp nhanh 185 bpm
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        tileColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF334155)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.monitor_heart, color: Color(0xFFEF4444), size: 22),
                        ),
                        title: const Text('Mô phỏng nhịp nhanh 185 BPM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Bắn mẫu telemetry nhịp tim cao khẩn cấp', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFF87171),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _simulateUrgentHeartRate();
                          },
                          child: const Text('Bắn mẫu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Test Thiếu Oxy SpO2 88%
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        tileColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF334155)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.air, color: Color(0xFFA855F7), size: 22),
                        ),
                        title: const Text('Mô phỏng thiếu oxy SpO2 88%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: const Text('Bắn mẫu telemetry SpO2 dưới ngưỡng an toàn', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC084FC),
                            side: const BorderSide(color: Color(0xFFA855F7)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _simulateHypoxiaSpO2();
                          },
                          child: const Text('Bắn mẫu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 3: Định vị & Bản đồ
                      const Text(
                        'ĐỊNH VỊ & BẢN ĐỒ VỊ TRÍ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),

                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        tileColor: const Color(0xFF0F172A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFF334155)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.map_outlined, color: Color(0xFF38BDF8), size: 22),
                        ),
                        title: Text('Tọa độ GPS: $_currentGps', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(_gpsStatus, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final loc = await LocationService.instance.getCurrentLocation();
                            if (mounted) setState(() => _currentGps = loc.coordinatesFormatted);
                            await LocationService.instance.openGoogleMaps(loc.latitude, loc.longitude, label: 'Vị trí Người cao tuổi: $_elderName');
                          },
                          icon: const Icon(Icons.open_in_new, size: 14, color: Color(0xFF38BDF8)),
                          label: const Text('Maps', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Device ID & Info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mã thiết bị: $_deviceId',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Máy chủ: ${ApiService.instance.activeServerUrl}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('HỦY GHÉP NỐI', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              _showDiagnosticTestLabSheet(context);
            },
            child: const Text('🧪 PHÒNG THỬ NGHIỆM', style: TextStyle(color: Color(0xFF38BDF8))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY BỎ', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _watchDisconnectDebounceTimer?.cancel();
      _watchDisconnectDebounceTimer = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_paired_watch_name');
      await ApiService.instance.unpair();
      if (mounted) {
        setState(() {
          _lastPairedWatchName = null;
        });
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

      // Kiểm tra tính sở hữu: Người cao tuổi trên máy có thuộc Người thân đang lưu hay không
      final currentElderId = await ApiService.instance.getElderProfileId();
      final canEnterHomeScreen = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder(currentElderId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => canEnterHomeScreen ? const HomeScreen() : const LoginScreen(),
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
        title: GestureDetector(
          onTap: _handleSecretTitleTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isServerOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isServerOnline
                      ? (ApiService.instance.activeServerUrl.contains('127.0.0.1')
                          ? 'Trực tuyến (Cáp USB)'
                          : (ApiService.instance.activeServerUrl.contains('trycloudflare.com') ||
                                  ApiService.instance.activeServerUrl.contains('azurewebsites.net') ||
                                  ApiService.instance.activeServerUrl.startsWith('https://'))
                              ? 'Trực tuyến (Internet/4G)'
                              : 'Trực tuyến (Wi-Fi LAN)')
                      : 'Ngoại tuyến (Offline)',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
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
            // Thẻ thông tin người cao tuổi (Thiết kế trực quan, ấm cúng, không rác kỹ thuật)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFF0284C7),
                    radius: 24,
                    child: Icon(Icons.person, color: Colors.white, size: 28),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        const Row(
                          children: [
                            Icon(Icons.verified_user_outlined, size: 13, color: Color(0xFF34D399)),
                            SizedBox(width: 4),
                            Text(
                              'Đang bảo vệ an toàn 24/7',
                              style: TextStyle(fontSize: 12, color: Color(0xFF34D399), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 13,
                              color: EmergencyEvidenceService.recentFix == null
                                  ? const Color(0xFFFBBF24)
                                  : const Color(0xFF38BDF8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _locatingGps
                                    ? 'Đang tìm vị trí vệ tinh...'
                                    : (EmergencyEvidenceService.recentFix == null
                                        ? 'Đang cập nhật vị trí bảo vệ'
                                        : 'Vị trí sẵn sàng gửi người thân'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: EmergencyEvidenceService.recentFix == null
                                      ? const Color(0xFFFBBF24)
                                      : const Color(0xFF94A3B8),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (!_backgroundGpsGranted)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: InkWell(
                              onTap: _enableBackgroundGps,
                              child: const Text(
                                '⚠️ Bật định vị nền để bảo vệ liên tục',
                                style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24), decoration: TextDecoration.underline),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cập nhật lại GPS',
                    onPressed: _locatingGps ? null : _prepareGps,
                    icon: _locatingGps
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                          )
                        : const Icon(Icons.my_location, color: Color(0xFF38BDF8), size: 22),
                  ),
                ],
              ),
            ),

            // Card Thiết bị đeo Galaxy Watch (Wear OS) / Apple Watch (watchOS)
            Builder(
              builder: (context) {
                final isConnected = _watchStatus.isConnected;
                final hasKnownWatch = (_watchStatus.watchName != null && _watchStatus.watchName!.isNotEmpty) ||
                    (_lastPairedWatchName != null && _lastPairedWatchName!.isNotEmpty) ||
                    _watchStatus.isPaired;
                final isBtOff = !isConnected && _watchStatus.reason == 'BLUETOOTH_OFF';
                final isDisconnected = !isConnected && hasKnownWatch;
                final watchTitle = isConnected
                    ? (_watchStatus.watchName ?? _lastPairedWatchName ?? _platformWatchTitle)
                    : (isDisconnected ? (_watchStatus.watchName ?? _lastPairedWatchName ?? _platformWatchTitle) : 'Chưa ghép nối đồng hồ');

                final String statusSubtext;
                final Color borderColor;
                final Color iconBgColor;
                final Color iconColor;
                final IconData iconData;
                final Color subtextColor;

                if (isConnected) {
                  final batteryPct = _watchStatus.batteryLevel;
                  final isCharging = _watchStatus.isCharging == true;
                  final isWorn = _watchStatus.isWorn;

                  if (isCharging) {
                    if (batteryPct == 100) {
                      statusSubtext = '🔋 Đã sạc đầy 100% · Nhớ đeo lại vào tay';
                      borderColor = const Color(0xFF10B981).withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFF064E3B).withValues(alpha: 0.6);
                      iconColor = const Color(0xFF34D399);
                      subtextColor = const Color(0xFF6EE7B7);
                      iconData = Icons.battery_charging_full_rounded;
                    } else {
                      final pctStr = batteryPct != null ? ' ($batteryPct%)' : '';
                      statusSubtext = '⚡ Đang sạc pin$pctStr · Tạm dừng sinh hiệu';
                      borderColor = const Color(0xFF38BDF8).withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFF0C4A6E).withValues(alpha: 0.6);
                      iconColor = const Color(0xFF38BDF8);
                      subtextColor = const Color(0xFF7DD3FC);
                      iconData = Icons.battery_charging_full_rounded;
                    }
                  } else if (isWorn == false) {
                    final pctStr = batteryPct != null ? ' · Pin $batteryPct%' : '';
                    if (batteryPct != null && batteryPct <= 20) {
                      statusSubtext = '⚠️ Đã tháo khỏi cổ tay · Pin yếu $batteryPct%';
                      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFF7F1D1D).withValues(alpha: 0.6);
                      iconColor = const Color(0xFFF87171);
                      subtextColor = const Color(0xFFFCA5A5);
                      iconData = Icons.battery_alert_rounded;
                    } else {
                      statusSubtext = '🟡 Đã tháo khỏi cổ tay$pctStr';
                      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFF78350F).withValues(alpha: 0.6);
                      iconColor = const Color(0xFFFBBF24);
                      subtextColor = const Color(0xFFFDE68A);
                      iconData = Icons.watch_off_outlined;
                    }
                  } else {
                    if (batteryPct != null && batteryPct <= 10) {
                      statusSubtext = '🚨 Pin đồng hồ sắp cạn ($batteryPct%) · Hãy sạc ngay';
                      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.9);
                      iconBgColor = const Color(0xFF7F1D1D).withValues(alpha: 0.7);
                      iconColor = const Color(0xFFF87171);
                      subtextColor = const Color(0xFFFCA5A5);
                      iconData = Icons.battery_alert_rounded;
                    } else if (batteryPct != null && batteryPct <= 20) {
                      statusSubtext = '⚠️ Pin đồng hồ yếu ($batteryPct%) · Vui lòng cắm sạc';
                      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFF78350F).withValues(alpha: 0.6);
                      iconColor = const Color(0xFFFBBF24);
                      subtextColor = const Color(0xFFFDE68A);
                      iconData = Icons.battery_alert_rounded;
                    } else {
                      final pctStr = batteryPct != null ? ' (Pin $batteryPct%)' : '';
                      statusSubtext = '🟢 Đã kết nối · Trên cổ tay$pctStr · $_platformSensorLabel';
                      borderColor = const Color(0xFF22C55E).withValues(alpha: 0.6);
                      iconBgColor = const Color(0xFF14532D).withValues(alpha: 0.5);
                      iconColor = const Color(0xFF4ADE80);
                      subtextColor = const Color(0xFF4ADE80);
                      iconData = Icons.watch;
                    }
                  }
                } else if (isDisconnected) {
                  if (isBtOff) {
                    statusSubtext = '🔴 Bluetooth đang tắt · Gạt bật để kết nối đồng hồ';
                    borderColor = const Color(0xFFEF4444).withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFF7F1D1D).withValues(alpha: 0.5);
                    iconColor = const Color(0xFFF87171);
                    subtextColor = const Color(0xFFF87171);
                    iconData = Icons.bluetooth_disabled_rounded;
                  } else if (_isDebouncingDisconnect) {
                    statusSubtext = '🟡 Đang tìm lại đồng hồ (tạm xa điện thoại)';
                    borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFF78350F).withValues(alpha: 0.5);
                    iconColor = const Color(0xFFFBBF24);
                    subtextColor = const Color(0xFFFDE68A);
                    iconData = Icons.watch_later_outlined;
                  } else {
                    statusSubtext = '🔴 Mất tín hiệu đồng hồ · Kiểm tra khoảng cách/Pin';
                    borderColor = const Color(0xFFEF4444).withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFF7F1D1D).withValues(alpha: 0.5);
                    iconColor = const Color(0xFFF87171);
                    subtextColor = const Color(0xFFF87171);
                    iconData = Icons.watch_off_outlined;
                  }
                } else {
                  statusSubtext = '⚪ $_platformWatchTitle (Chạm để quét & kiểm tra)';
                  borderColor = const Color(0xFF475569).withValues(alpha: 0.4);
                  iconBgColor = const Color(0xFF1E293B);
                  iconColor = const Color(0xFF94A3B8);
                  subtextColor = const Color(0xFF94A3B8);
                  iconData = Icons.watch;
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: isBtOff ? _openBluetoothSettings : () => _checkWatchStatus(showFeedback: true),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: iconBgColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                iconData,
                                color: iconColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    watchTitle,
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
                                    statusSubtext,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: subtextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isBtOff)
                              InkWell(
                                onTap: _openBluetoothSettings,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626).withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFEF4444)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.bluetooth_searching, size: 14, color: Color(0xFFF87171)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Bật BT',
                                        style: TextStyle(
                                          color: Color(0xFFF87171),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (_isDebouncingDisconnect)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFFBBF24),
                                ),
                              )
                            else if (isConnected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF22C55E),
                                size: 18,
                              )
                            else
                              const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF64748B),
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (isBtOff)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 13, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Mẹo: Vuốt mép trên màn hình xuống & chạm icon Bluetooth để bật lại nhanh',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFFFDE68A).withValues(alpha: 0.9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
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
