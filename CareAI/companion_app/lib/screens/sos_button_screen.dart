import '../theme/careai_theme.dart';

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
import '../services/voice_guidance_service.dart';

import 'package:intl/intl.dart';

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

  Timer? _incidentPollTimer;
  String? _activeIncidentStatus;
  String? _acknowledgedByName;
  DateTime? _acknowledgedAt;
  String? _acknowledgedNote;
  bool _acknowledgedAnnounced = false;

  WatchStatus _watchStatus = const WatchStatus(isConnected: false);
  String? _lastPairedWatchName;
  String? _customWatchAlias;
  Timer? _watchStatusTimer;
  Timer? _watchDisconnectDebounceTimer;
  bool _isDebouncingDisconnect = false;
  static const Duration _kWatchDisconnectDebounce = Duration(minutes: 3);
  Timer? _healthCheckTimer;
  StreamSubscription<FallEvent>? _fallSubscription;
  StreamSubscription<Map<String, dynamic>>? _manualSosSubscription;
  StreamSubscription<WatchStatus>? _watchStatusSubscription;
  DateTime? _sosStartTime;
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

    _fallSubscription = FallService.instance.onFallDetected.listen((fallEvent) {
      if (mounted) {
        _showFallCountdownModal(fallEvent);
      }
    });

    // Lắng nghe lệnh phát tín hiệu SOS trực tiếp từ đồng hồ (Bỏ qua đếm ngược té ngã vì cụ chủ động bấm nút)
    _manualSosSubscription = FallService.instance.onManualSosTriggered.listen((
      payload,
    ) {
      if (mounted) {
        final packetId =
            payload['packetId'] as String? ??
            'SOS_WATCH_${DateTime.now().millisecondsSinceEpoch}';
        _sosStartTime = DateTime.now();
        setState(() {
          _isSosActive = true;
          _lastSosPacketId = packetId;
          _activeIncidentStatus = 'OPEN';
          _acknowledgedAnnounced = false;
        });
        _startIncidentPolling();
      }
    });

    // Lắng nghe sự kiện kết nối/ngắt kết nối đồng hồ thời gian thực (Event-Driven 0.1 giây từ Native Android/iOS)
    _watchStatusSubscription = FallService.instance.onWatchConnectionChanged
        .listen((status) {
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

    // Fallback dự phòng kiểm tra trạng thái Bluetooth đồng hồ (chu kỳ 5 phút để tiết kiệm pin tối đa nhờ Event-Driven)
    _watchStatusTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkWatchStatus();
    });

    // Lắng nghe tín hiệu thiết bị bị hủy ghép nối từ xa (UC-12)
    ApiService.instance.deviceUnpairedNotifier.addListener(_onRemoteDeviceUnpaired);

    // Kích hoạt chu kỳ đồng bộ ngoại tuyến định kỳ
    SyncService.instance.startPeriodicSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkWatchStatus());
      unawaited(_checkServerHealth());
      unawaited(_loadPendingCount());
      unawaited(_sendElderDeviceHeartbeat());
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
    final savedAlias = prefs.getString('custom_watch_alias');
    final saved = prefs.getString('last_paired_watch_name');
    if (mounted) {
      setState(() {
        if (savedAlias != null && savedAlias.isNotEmpty) {
          _customWatchAlias = savedAlias;
        }
        if (saved != null && saved.isNotEmpty) {
          _lastPairedWatchName = saved;
        }
      });
    }
  }

  String get _effectiveWatchDisplayName {
    if (_customWatchAlias != null && _customWatchAlias!.trim().isNotEmpty) {
      return _customWatchAlias!.trim();
    }
    final platformName = defaultTargetPlatform == TargetPlatform.iOS
        ? 'Apple Watch'
        : 'Galaxy Watch';
    final isStatusGeneric =
        _watchStatus.watchName == null ||
        _watchStatus.watchName!.trim().isEmpty ||
        _watchStatus.watchName == 'Apple Watch' ||
        _watchStatus.watchName == 'Galaxy Watch';
    final isSavedSpecific =
        _lastPairedWatchName != null &&
        _lastPairedWatchName!.trim().isNotEmpty &&
        _lastPairedWatchName != 'Apple Watch' &&
        _lastPairedWatchName != 'Galaxy Watch';

    if (!isStatusGeneric &&
        _watchStatus.watchName != null &&
        _watchStatus.watchName!.isNotEmpty) {
      return _watchStatus.watchName!;
    }
    if (isSavedSpecific) {
      return _lastPairedWatchName!;
    }
    return _watchStatus.watchName ?? _lastPairedWatchName ?? platformName;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopIncidentPolling();
    _healthCheckTimer?.cancel();
    _watchStatusTimer?.cancel();
    _watchDisconnectDebounceTimer?.cancel();
    _fallSubscription?.cancel();
    _manualSosSubscription?.cancel();
    _watchStatusSubscription?.cancel();
    _rippleController.dispose();
    FallService.instance.stopPhoneAccelerometerDetector();
    ApiService.instance.deviceUnpairedNotifier.removeListener(_onRemoteDeviceUnpaired);
    SyncService.instance.stopPeriodicSync();
    super.dispose();
  }

  void _onRemoteDeviceUnpaired() {
    if (!mounted) return;
    if (ApiService.instance.deviceUnpairedNotifier.value) {
      ApiService.instance.deviceUnpairedNotifier.value = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thiết bị này đã được người bảo hộ chính hủy ghép nối từ xa.'),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
      );
    }
  }

  void _startIncidentPolling() {
    _incidentPollTimer?.cancel();
    _sosStartTime ??= DateTime.now();
    _scheduleNextIncidentPoll();
    unawaited(_pollActiveIncident());
  }

  void _scheduleNextIncidentPoll() {
    _incidentPollTimer?.cancel();
    if (!mounted || !_isSosActive) return;

    // Tính toán chu kỳ thích ứng (Adaptive Interval):
    // - Khi chưa được tiếp nhận (OPEN):
    //   * 3 phút đầu: 3 giây (đảm bảo phản hồi tức thì dưới 3s cho người già)
    //   * Sau 3 phút: 10 giây (tiết kiệm pin khi người thân chưa kịp mở điện thoại)
    // - Khi đã được tiếp nhận (ACKNOWLEDGED):
    //   * 8 giây (còi đã tắt, giọng nói an tâm đã phát, kiểm tra RESOLVED tiết kiệm pin)
    // - Quá 2 giờ: giãn ra 60 giây (bảo vệ pin nếu sự cố bị lãng quên hoặc treo)
    final now = DateTime.now();
    final elapsedSec = _sosStartTime != null
        ? now.difference(_sosStartTime!).inSeconds
        : 0;

    Duration interval;
    if (elapsedSec > 7200) {
      interval = const Duration(seconds: 60);
    } else if (_activeIncidentStatus == 'ACKNOWLEDGED') {
      interval = const Duration(seconds: 8);
    } else if (elapsedSec < 180) {
      interval = const Duration(seconds: 3);
    } else {
      interval = const Duration(seconds: 10);
    }

    _incidentPollTimer = Timer(interval, () {
      if (mounted && _isSosActive) {
        _pollActiveIncident();
        _scheduleNextIncidentPoll();
      }
    });
  }

  void _stopIncidentPolling() {
    _incidentPollTimer?.cancel();
    _incidentPollTimer = null;
    _sosStartTime = null;
  }

  Future<void> _pollActiveIncident() async {
    if (!mounted) return;
    try {
      final incident = await ApiService.instance.getActiveIncident();
      if (!mounted || incident == null) return;

      if (incident.hasActiveIncident) {
        if (incident.status == 'ACKNOWLEDGED') {
          final wasAck = _activeIncidentStatus == 'ACKNOWLEDGED';
          setState(() {
            _isSosActive = true;
            _activeIncidentStatus = 'ACKNOWLEDGED';
            _acknowledgedByName = incident.acknowledgedByName;
            _acknowledgedAt = incident.acknowledgedAt;
            _acknowledgedNote = incident.acknowledgedNote;
          });

          if (!wasAck) {
            _scheduleNextIncidentPoll();
          }

          // Ngắt còi hú nếu còn đang phát
          unawaited(FallService.instance.stopEmergencySound());

          // Đồng bộ sang Apple Watch / Wear OS
          unawaited(
            FallService.instance.notifyIncidentStatusToWatch(
              status: 'ACKNOWLEDGED',
              acknowledgedByName: incident.acknowledgedByName,
              notes: incident.acknowledgedNote,
              incidentId: incident.incidentId,
            ),
          );

          // Phát âm báo giọng nói tiếng Việt an tâm (một lần duy nhất)
          if (!_acknowledgedAnnounced) {
            _acknowledgedAnnounced = true;
            final who =
                (incident.acknowledgedByName != null &&
                    incident.acknowledgedByName!.trim().isNotEmpty)
                ? incident.acknowledgedByName!.trim()
                : 'Người thân';
            final text = '$who đã tiếp nhận hỗ trợ.';
            unawaited(VoiceGuidanceService.instance.speak(text));
          }
        } else if (incident.status == 'OPEN') {
          if (_activeIncidentStatus != 'OPEN') {
            setState(() {
              _isSosActive = true;
              _activeIncidentStatus = 'OPEN';
            });
          }
        }
      } else {
        // Sự cố đã được đóng (RESOLVED) hoặc không còn sự cố nào trên máy chủ
        if (_isSosActive || _activeIncidentStatus != null) {
          final resolvedName = incident.resolvedByName;
          _stopIncidentPolling();
          setState(() {
            _isSosActive = false;
            _activeIncidentStatus = null;
            _acknowledgedByName = null;
            _acknowledgedAt = null;
            _acknowledgedNote = null;
            _acknowledgedAnnounced = false;
          });

          // Ngắt còi hú
          unawaited(FallService.instance.stopEmergencySound());

          // Báo đồng hồ đưa về bình thường
          unawaited(
            FallService.instance.notifyIncidentStatusToWatch(
              status: 'RESOLVED',
              incidentId: incident.incidentId,
            ),
          );

          // Phát âm thông báo an toàn
          final text = (resolvedName != null && resolvedName.trim().isNotEmpty)
              ? 'Sự cố đã được $resolvedName giải quyết an toàn.'
              : 'Sự cố đã được xử lý hoàn tất.';
          unawaited(VoiceGuidanceService.instance.speak(text));

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(text),
                backgroundColor: const Color(0xFF059669),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    } catch (_) {}
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
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
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

  Future<void> _applyWatchStatus(
    WatchStatus status, {
    bool showFeedback = false,
  }) async {
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

        final isStatusGeneric =
            status.watchName == null ||
            status.watchName!.trim().isEmpty ||
            status.watchName == 'Apple Watch' ||
            status.watchName == 'Galaxy Watch';
        final isSavedSpecific =
            savedWatchName != null &&
            savedWatchName.trim().isNotEmpty &&
            savedWatchName != 'Apple Watch' &&
            savedWatchName != 'Galaxy Watch';

        if (!isStatusGeneric) {
          _lastPairedWatchName = status.watchName;
          await prefs.setString('last_paired_watch_name', status.watchName!);
        } else if (isSavedSpecific) {
          _lastPairedWatchName = savedWatchName;
        }

        final effectiveName = _effectiveWatchDisplayName;

        unawaited(
          ApiService.instance.syncConnectedWatch(
            effectiveName,
            isConnected: true,
            isWorn: status.isWorn,
            isCharging: status.isCharging,
            batteryLevel: status.batteryLevel,
            todaySteps: status.todaySteps,
            heartRate: status.heartRate,
            spo2: status.spo2,
            bpSystolic: status.bpSystolic,
            bpDiastolic: status.bpDiastolic,
            sleepMinutes: status.sleepMinutes,
            deepSleepMinutes: status.deepSleepMinutes,
            coreSleepMinutes: status.coreSleepMinutes,
            remSleepMinutes: status.remSleepMinutes,
            awakeMinutes: status.awakeMinutes,
            wakeCount: status.wakeCount,
            minSleepingHr: status.minSleepingHr,
            avgSleepingHr: status.avgSleepingHr,
            minNightSpo2: status.minNightSpo2,
            nightSpo2DipsCount: status.nightSpo2DipsCount,
            breathingDisturbances: status.breathingDisturbances,
            supportedMetrics: status.supportedMetrics,
          ),
        );
        unawaited(() async {
          final serverUrl = await ApiService.instance.getServerUrl();
          final devId = await ApiService.instance.getDeviceId();
          final devToken = await ApiService.instance.getDeviceToken();
          if (devId != null &&
              devToken != null &&
              devId.isNotEmpty &&
              devToken.isNotEmpty) {
            await FallService.instance.syncWatchCredentials(
              backendUrl: serverUrl,
              deviceId: devId,
              deviceToken: devToken,
              elderName: _elderName,
            );
          }
        }());

        final isWatchWornAndActive =
            (status.isWorn ?? true) && !(status.isCharging ?? false);
        if (isWatchWornAndActive) {
          // Người già đang đeo đồng hồ: Tắt hoàn toàn cảm biến nền điện thoại để tiết kiệm 100% pin
          FallService.instance.stopPhoneAccelerometerDetector();
        } else {
          // Đồng hồ đã tháo hoặc đang cắm sạc: Kích hoạt cảm biến điện thoại dự phòng
          FallService.instance.startPhoneAccelerometerDetector();
        }
      } else {
        // Đồng hồ mất kết nối: Tự động kích hoạt cảm biến điện thoại dự phòng bảo vệ người già
        FallService.instance.startPhoneAccelerometerDetector();

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
          if (_lastPairedWatchName != null &&
              _lastPairedWatchName!.isNotEmpty) {
            unawaited(
              ApiService.instance.syncConnectedWatch(
                _lastPairedWatchName!,
                isConnected: false,
                disconnectReason: 'BLUETOOTH_OFF',
              ),
            );
          }
        } else {
          // Trường hợp B: Mất sóng BLE tạm thời do đi xa / qua tường -> Giữ trạng thái debounce 3 phút chống báo động giả
          if (_watchDisconnectDebounceTimer == null ||
              !_watchDisconnectDebounceTimer!.isActive) {
            setState(() {
              _watchStatus = status;
              _isDebouncingDisconnect = true;
              if (savedWatchName != null && savedWatchName.isNotEmpty) {
                _lastPairedWatchName = savedWatchName;
              }
            });
            _watchDisconnectDebounceTimer = Timer(
              _kWatchDisconnectDebounce,
              () {
                if (mounted) {
                  setState(() {
                    _isDebouncingDisconnect = false;
                  });
                  if (!_watchStatus.isConnected &&
                      _lastPairedWatchName != null &&
                      _lastPairedWatchName!.isNotEmpty) {
                    debugPrint(
                      '[SosButtonScreen] Đã quá 3 phút mất sóng BLE -> Xác nhận ngắt kết nối thật, thông báo lên máy chủ',
                    );
                    unawaited(
                      ApiService.instance.syncConnectedWatch(
                        _lastPairedWatchName!,
                        isConnected: false,
                        disconnectReason: 'SIGNAL_LOST',
                      ),
                    );
                  }
                }
              },
            );
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
        final platformName = defaultTargetPlatform == TargetPlatform.iOS
            ? 'Apple Watch'
            : 'Galaxy Watch';
        final channelDesc = defaultTargetPlatform == TargetPlatform.iOS
            ? 'Bluetooth / Apple Watch App'
            : 'Bluetooth / Galaxy Wearable';
        final effectiveWatchName = _effectiveWatchDisplayName;
        final hasKnownWatch =
            status.isPaired ||
            _lastPairedWatchName != null ||
            (_customWatchAlias != null && _customWatchAlias!.trim().isNotEmpty);
        String feedbackMsg;
        if (status.isConnected) {
          feedbackMsg =
              '🟢 Đã kết nối: $effectiveWatchName (${defaultTargetPlatform == TargetPlatform.iOS ? "watchOS" : "Wear OS"})';
        } else if (status.reason == 'BLUETOOTH_OFF') {
          feedbackMsg =
              '🔴 Bluetooth đang tắt: $effectiveWatchName (Bật lại Bluetooth trên điện thoại)';
        } else if (hasKnownWatch) {
          feedbackMsg =
              '🔴 Mất tín hiệu: $effectiveWatchName (Kiểm tra khoảng cách/Pin đồng hồ)';
        } else {
          feedbackMsg =
              '⚪ Chưa phát hiện $platformName kết nối (Kiểm tra qua $channelDesc)';
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

    if (devId != null &&
        devToken != null &&
        devId.isNotEmpty &&
        devToken.isNotEmpty) {
      unawaited(
        FallService.instance.syncWatchCredentials(
          backendUrl: serverUrl,
          deviceId: devId,
          deviceToken: devToken,
          elderName: name,
        ),
      );
      unawaited(_sendElderDeviceHeartbeat());
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
      final loc = await LocationService.instance.getCurrentLocation(
        requestPermissionIfDenied: false,
      );
      if (mounted) {
        setState(() {
          _currentGps = loc.coordinatesFormatted;
        });
      }
    } catch (_) {}
  }

  int _heartbeatTicks = 0;

  Future<void> _sendElderDeviceHeartbeat() async {
    final devId = await ApiService.instance.getDeviceId();
    final devToken = await ApiService.instance.getDeviceToken();
    if (devId == null || devToken == null || devId.isEmpty || devToken.isEmpty) {
      return;
    }

    // Gửi nhịp đập của điện thoại Người cao tuổi để app Người thân luôn thấy trạng thái ONLINE
    unawaited(ApiService.instance.sendHeartbeat());

    // Nếu đồng hồ đang kết nối, đồng bộ trạng thái đồng hồ lên đám mây
    if (_watchStatus.isConnected) {
      final watchName = _effectiveWatchDisplayName;

      unawaited(
        ApiService.instance.syncConnectedWatch(
          watchName,
          isConnected: true,
          isWorn: _watchStatus.isWorn,
          isCharging: _watchStatus.isCharging,
          batteryLevel: _watchStatus.batteryLevel,
          todaySteps: _watchStatus.todaySteps,
          heartRate: _watchStatus.heartRate,
          spo2: _watchStatus.spo2,
          bpSystolic: _watchStatus.bpSystolic,
          bpDiastolic: _watchStatus.bpDiastolic,
          sleepMinutes: _watchStatus.sleepMinutes,
          deepSleepMinutes: _watchStatus.deepSleepMinutes,
          coreSleepMinutes: _watchStatus.coreSleepMinutes,
          remSleepMinutes: _watchStatus.remSleepMinutes,
          awakeMinutes: _watchStatus.awakeMinutes,
          wakeCount: _watchStatus.wakeCount,
          minSleepingHr: _watchStatus.minSleepingHr,
          avgSleepingHr: _watchStatus.avgSleepingHr,
          minNightSpo2: _watchStatus.minNightSpo2,
          nightSpo2DipsCount: _watchStatus.nightSpo2DipsCount,
          breathingDisturbances: _watchStatus.breathingDisturbances,
          supportedMetrics: _watchStatus.supportedMetrics,
        ),
      );
    }
  }

  Future<void> _checkServerHealth() async {
    final online = await ApiService.instance.checkServerHealth();
    if (mounted) {
      final wasOffline = !_isServerOnline;
      setState(() {
        _isServerOnline = online;
      });

      if (online) {
        _heartbeatTicks++;
        // Gửi nhịp đập thiết bị định kỳ mỗi 5 phút (mỗi 60 chu kỳ timer 5s) hoặc ngay khi máy vừa có mạng lại
        if (wasOffline || _heartbeatTicks % 60 == 1) {
          unawaited(_sendElderDeviceHeartbeat());
        }

        // Tự động duy trì hoặc khôi phục kiểm tra phản hồi sự cố khép kín
        if (_isSosActive && _incidentPollTimer == null) {
          _startIncidentPolling();
        } else if (!_isSosActive && _heartbeatTicks % 6 == 1) {
          unawaited(_pollActiveIncident());
        }
      }

      // Tự động xả hàng đợi ngoại tuyến ngay khi máy có kết nối trở lại
      if (online && (wasOffline || _pendingPacketCount > 0)) {
        SyncService.instance.syncOfflineSpool().then((result) async {
          await _loadPendingCount();
          final lastSync = await LocalOfflineStore.instance
              .getLastSyncTimestamp();
          if (mounted && result.syncedCount > 0) {
            setState(() {
              _lastSyncTime = lastSync;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Tự động đồng bộ thành công: Đã gửi ${result.syncedCount} gói tin khẩn cấp!',
                ),
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
            _activeIncidentStatus = 'OPEN';
            _acknowledgedAnnounced = false;
          });
          _startIncidentPolling();
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
      samples.add(
        TelemetrySample(
          metricType: 'HEART_RATE',
          value: lastHr,
          unit: 'BPM',
          timestamp: now,
        ),
      );
    }
    if (lastSpo2 != null && lastSpo2 > 0) {
      samples.add(
        TelemetrySample(
          metricType: 'SPO2',
          value: lastSpo2,
          unit: '%',
          timestamp: now,
        ),
      );
    }

    // TUÂN THỦ NGHIÊM NGẶT: Lấy tọa độ GPS thực tế từ phần cứng thiết bị (Không dùng bản đồ Trung Quốc)
    final recentFix = EmergencyEvidenceService.recentFix;
    final gpsResult = await LocationService.instance.getCurrentLocation();
    final realGpsLocation = gpsResult.isRealGps
        ? gpsResult.coordinatesFormatted
        : (recentFix != null && !recentFix.isSimulated
              ? recentFix.coordinates
              : null);
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
      _activeIncidentStatus = 'OPEN';
      _acknowledgedAnnounced = false;
    });
    _startIncidentPolling();

    // BƯỚC 2: Thử Fast-Lane HTTP POST trực tiếp lên máy chủ
    try {
      final result = await ApiService.instance.sendFastLaneSosWithResult(
        sosRequest,
      );
      if (result.accepted) {
        await LocalOfflineStore.instance.markPacketSynced(packetId);
        if (result.incidentId != null) {
          unawaited(
            EmergencyEvidenceService.attachLocationWhenReady(
              result.incidentId!,
              locationTask,
              initiallySentGps: realGpsLocation,
            ),
          );
          unawaited(
            EmergencyEvidenceService.captureAndUploadPhoto(result.incidentId!),
          );
        }
      }
    } catch (_) {
      // Ngoại tuyến: Sự cố đã được lưu an toàn trong SQLite Outbox
    }

    await _loadPendingCount();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tín hiệu cấp cứu đã được ghi nhận và gửi đến người thân!',
          ),
          backgroundColor: Color(0xFFDC2626),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleManualSync() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đang đồng bộ dữ liệu ngoại tuyến...'),
        duration: Duration(seconds: 1),
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Để gửi GPS khi app ở nền, chọn “Cho phép mọi lúc” trong quyền vị trí của CareAI.',
            ),
          ),
        );
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
          content: Text(
            'Mẫu nhịp nhanh 185 bpm đã được gửi hoặc lưu vào hàng đợi.',
          ),
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
          content: Text(
            'Mẫu thiếu oxy SpO2 88% đã được gửi hoặc lưu vào hàng đợi.',
          ),
          backgroundColor: Color(0xFF7C3AED),
        ),
      );
    }
  }

  void _showDiagnosticTestLabSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
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
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.biotech_rounded,
                              color: Color(0xFFF59E0B),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Phòng Thử Nghiệm Tín Hiệu',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: CareAiColors.ink,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Chuyên biệt cho kiểm thử lâm sàng & phần cứng',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF7D7168),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: CareAiColors.secondary,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE4DACD), height: 1),
                      const SizedBox(height: 14),

                      // Section 1: Mô phỏng biến cố khẩn cấp
                      const Text(
                        'MÔ PHỎNG BIẾN CỐ KHẨN CẤP',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7D7168),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Test Ngã Button
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        tileColor: const Color(0xFFFAF7F2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFFFEDE7)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626)
                                .withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.personal_injury,
                            color: Color(0xFFEF4444),
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Mô phỏng té ngã phần cứng',
                          style: TextStyle(
                            color: CareAiColors.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Kích hoạt chu trình đếm ngược 15s và còi SOS',
                          style: TextStyle(
                            color: Color(0xFF7D7168),
                            fontSize: 14,
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final eventId = await FallService.instance
                                .simulateHardwareFall();
                            if (context.mounted && eventId != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '⚡ Đã kích hoạt mô phỏng ngã phần cứng ($eventId)',
                                  ),
                                  backgroundColor: const Color(0xFFB91C1C),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'Kích hoạt',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 2: Sinh hiệu lâm sàng
                      const Text(
                        'THỬ NGHIỆM SINH HIỆU LÂM SÀNG',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7D7168),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Test Nhịp nhanh 185 bpm
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        tileColor: const Color(0xFFFAF7F2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE4DACD)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444)
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.monitor_heart,
                            color: Color(0xFFEF4444),
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Mô phỏng nhịp nhanh 185 BPM',
                          style: TextStyle(
                            color: CareAiColors.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Bắn mẫu telemetry nhịp tim cao khẩn cấp',
                          style: TextStyle(
                            color: Color(0xFF7D7168),
                            fontSize: 14,
                          ),
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC93B2B),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _simulateUrgentHeartRate();
                          },
                          child: const Text(
                            'Bắn mẫu',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Test Thiếu Oxy SpO2 88%
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        tileColor: const Color(0xFFFAF7F2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE4DACD)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA855F7)
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.air,
                            color: Color(0xFFA855F7),
                            size: 22,
                          ),
                        ),
                        title: const Text(
                          'Mô phỏng thiếu oxy SpO2 88%',
                          style: TextStyle(
                            color: CareAiColors.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Bắn mẫu telemetry SpO2 dưới ngưỡng an toàn',
                          style: TextStyle(
                            color: Color(0xFF7D7168),
                            fontSize: 14,
                          ),
                        ),
                        trailing: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFC084FC),
                            side: const BorderSide(color: Color(0xFFA855F7)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _simulateHypoxiaSpO2();
                          },
                          child: const Text(
                            'Bắn mẫu',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 3: Định vị & Bản đồ
                      const Text(
                        'ĐỊNH VỊ & BẢN ĐỒ VỊ TRÍ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7D7168),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        tileColor: const Color(0xFFFAF7F2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE4DACD)),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF456624)
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.map_outlined,
                            color: Color(0xFF456624),
                            size: 22,
                          ),
                        ),
                        title: Text(
                          'Tọa độ GPS: $_currentGps',
                          style: const TextStyle(
                            color: CareAiColors.ink,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _gpsStatus,
                          style: const TextStyle(
                            color: Color(0xFF7D7168),
                            fontSize: 14,
                          ),
                        ),
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final loc = await LocationService.instance
                                .getCurrentLocation();
                            if (mounted) {
                              setState(
                                () => _currentGps = loc.coordinatesFormatted,
                              );
                            }
                            await LocationService.instance.openGoogleMaps(
                              loc.latitude,
                              loc.longitude,
                              label: 'Vị trí Người cao tuổi: $_elderName',
                            );
                          },
                          icon: const Icon(
                            Icons.open_in_new,
                            size: 14,
                            color: Color(0xFF456624),
                          ),
                          label: const Text(
                            'Maps',
                            style: TextStyle(
                              color: Color(0xFF456624),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Device ID & Info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF7F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE4DACD)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mã thiết bị: $_deviceId',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF7D7168),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Máy chủ: ${ApiService.instance.activeServerUrl}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF7D7168),
                              ),
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

  /// Đổi tên thân thuộc cho đồng hồ (biệt danh) để người thân dễ nhận biết
  Future<void> _showEditWatchNameDialog(String currentName) async {
    final isGeneric =
        currentName == 'Apple Watch' ||
        currentName == 'Galaxy Watch' ||
        currentName == 'Apple Watch (watchOS)' ||
        currentName == 'Galaxy Watch (Wear OS)' ||
        currentName == 'Chưa kết nối đồng hồ' ||
        currentName == 'Chưa ghép nối đồng hồ';
    final controller = TextEditingController(
      text: isGeneric ? '' : currentName,
    );
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE4DACD)),
        ),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFF456624), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Tên đồng hồ',
                style: TextStyle(
                  color: CareAiColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đặt tên quen thuộc để gia đình dễ nhận ra đồng hồ.',
                  style: TextStyle(
                    color: Color(0xFF7D7168),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: CareAiColors.ink, fontSize: 15),
                  decoration: InputDecoration(
                    labelText: 'Tên đồng hồ',
                    hintStyle: const TextStyle(color: Color(0xFF7D7168)),
                    filled: true,
                    fillColor: const Color(0xFFFAF7F2),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFFE4DACD)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(
                        color: Color(0xFF456624),
                        width: 1.5,
                      ),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Vui lòng nhập tên cho đồng hồ';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Hủy',
              style: TextStyle(
                color: Color(0xFF7D7168),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A3020),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text(
              'Lưu tên',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_watch_alias', newName);
      setState(() {
        _customWatchAlias = newName;
      });
      unawaited(
        ApiService.instance.syncConnectedWatch(
          newName,
          isConnected: _watchStatus.isConnected,
          isWorn: _watchStatus.isWorn,
          isCharging: _watchStatus.isCharging,
          batteryLevel: _watchStatus.batteryLevel,
          todaySteps: _watchStatus.todaySteps,
          heartRate: _watchStatus.heartRate,
          spo2: _watchStatus.spo2,
          bpSystolic: _watchStatus.bpSystolic,
          bpDiastolic: _watchStatus.bpDiastolic,
          sleepMinutes: _watchStatus.sleepMinutes,
          deepSleepMinutes: _watchStatus.deepSleepMinutes,
          coreSleepMinutes: _watchStatus.coreSleepMinutes,
          remSleepMinutes: _watchStatus.remSleepMinutes,
          awakeMinutes: _watchStatus.awakeMinutes,
          wakeCount: _watchStatus.wakeCount,
          minSleepingHr: _watchStatus.minSleepingHr,
          avgSleepingHr: _watchStatus.avgSleepingHr,
          minNightSpo2: _watchStatus.minNightSpo2,
          nightSpo2DipsCount: _watchStatus.nightSpo2DipsCount,
          breathingDisturbances: _watchStatus.breathingDisturbances,
          supportedMetrics: _watchStatus.supportedMetrics,
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã cập nhật tên đồng hồ: $newName'),
            backgroundColor: const Color(0xFF4A3020),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Mở hộp thoại Cài Đặt Thiết Bị (Thanh lịch, không gây hoang mang, tách bạch chức năng)
  Future<void> _showSettingsDialog() async {
    final isConnected = _watchStatus.isConnected;
    final hasKnownWatch =
        (_watchStatus.watchName != null &&
            _watchStatus.watchName!.isNotEmpty) ||
        (_lastPairedWatchName != null && _lastPairedWatchName!.isNotEmpty) ||
        _customWatchAlias != null ||
        _watchStatus.isPaired;
    final watchDisplayName = _effectiveWatchDisplayName;

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE4DACD), width: 1),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header với icon cài đặt & nút đóng
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF456624)
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.settings_outlined,
                          color: Color(0xFF456624),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cài đặt thiết bị',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: CareAiColors.ink,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Kết nối và hồ sơ',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF7D7168),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: CareAiColors.secondary,
                          size: 20,
                        ),
                        tooltip: 'Đóng cài đặt',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFFE4DACD), height: 1),
                  const SizedBox(height: 10),

                  // Thẻ thông tin Apple Watch (Gọn gàng, vừa khít, cùng một hàng, không thừa không gian)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: CareAiColors.canvas,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: CareAiColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.watch_outlined,
                              size: 24,
                              color: CareAiColors.brown,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                watchDisplayName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: CareAiColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isConnected
                              ? '${_watchStatus.batteryLevel != null ? 'Pin ${_watchStatus.batteryLevel}%' : 'Đã kết nối'}${_watchStatus.isWorn == true ? ' · Đang đeo' : ''}'
                              : 'Chưa nhận tín hiệu',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: CareAiColors.secondary,
                          ),
                        ),
                        if (hasKnownWatch || isConnected) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showEditWatchNameDialog(watchDisplayName);
                                },
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text('Đổi tên đồng hồ'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _handleUnpairWatchOnly();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: CareAiColors.amber,
                                ),
                                icon: const Icon(
                                  Icons.link_off_rounded,
                                  size: 18,
                                ),
                                label: const Text('Ngắt kết nối'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Nút 1: Phòng thử nghiệm tín hiệu
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF456624),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.biotech_outlined, size: 17),
                    label: const Text(
                      'Mở Phòng Thử Nghiệm Tín Hiệu',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showDiagnosticTestLabSheet(context);
                    },
                  ),
                  const SizedBox(height: 6),
                  const Divider(color: Color(0xFFE4DACD), height: 1),
                  const SizedBox(height: 10),

                  // Nút 2: ĐĂNG XUẤT HỒ SƠ (Gọn gàng, đúng nhãn yêu cầu)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(
                        color: Color(0xFFDC2626),
                        width: 1.2,
                      ),
                      backgroundColor: const Color(0xFFFFEDE7)
                          .withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 16),
                    label: const Text(
                      'ĐĂNG XUẤT HỒ SƠ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleLogoutAccount();
                    },
                  ),
                  const SizedBox(height: 8),

                  // Nút 3: HỦY BỎ (Dưới cùng, đơn giản, rõ nét)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: CareAiColors.brown,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Đóng',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
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

  /// Ngắt liên kết riêng biệt với Apple Watch (Vẫn giữ nguyên app SOS và hồ sơ người già trên iPhone)
  Future<void> _handleUnpairWatchOnly() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE4DACD)),
        ),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: Color(0xFFF97316), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ngắt Liên Kết Đồng Hồ?',
                style: TextStyle(
                  color: CareAiColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Đồng hồ sẽ ngừng đo nhịp tim và phát hiện té ngã.\n\nNút SOS khẩn cấp và định vị GPS trên chiếc điện thoại này vẫn hoạt động bình thường để bảo vệ bạn.',
          style: TextStyle(color: Color(0xFF5C493B), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'GIỮ KẾT NỐI',
              style: TextStyle(color: CareAiColors.secondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'XÁC NHẬN NGẮT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _watchDisconnectDebounceTimer?.cancel();
      _watchDisconnectDebounceTimer = null;
      await FallService.instance.unpairWatch();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_paired_watch_name');
      await prefs.remove('custom_watch_alias');
      if (mounted) {
        setState(() {
          _lastPairedWatchName = null;
          _customWatchAlias = null;
          _watchStatus = const WatchStatus(isConnected: false);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã ngắt liên kết đồng hồ. Nút SOS trên điện thoại vẫn sẵn sàng bảo vệ bạn.',
            ),
            backgroundColor: Color(0xFFFAF7F2),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Đăng xuất toàn bộ hồ sơ người già (Hủy cả iPhone lẫn Apple Watch / Reset App)
  Future<void> _handleLogoutAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFFFEDE7)),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFEF4444),
              size: 24,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Xác Nhận Đăng Xuất Hồ Sơ?',
                style: TextStyle(
                  color: CareAiColors.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Toàn bộ tính năng bảo vệ, định vị và gửi tín hiệu SOS của ông/bà ${_elderName.isNotEmpty ? _elderName : "người cao tuổi"} trên CẢ ĐIỆN THOẠI VÀ ĐỒNG HỒ sẽ dừng hoạt động.\n\nBạn sẽ cần quét mã PIN mới để kết nối lại.',
          style: const TextStyle(
            color: Color(0xFF5C493B),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'HỦY BỎ',
              style: TextStyle(color: CareAiColors.secondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'ĐĂNG XUẤT',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _watchDisconnectDebounceTimer?.cancel();
      _watchDisconnectDebounceTimer = null;
      await FallService.instance.unpairWatch();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_paired_watch_name');
      await prefs.remove('custom_watch_alias');
      await ApiService.instance.unpair();
      if (mounted) {
        setState(() {
          _lastPairedWatchName = null;
          _customWatchAlias = null;
          _watchStatus = const WatchStatus(isConnected: false);
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A3020),
            ),
            child: const Text(
              'CHUYỂN ĐỔI',
              style: TextStyle(color: Colors.white),
            ),
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
      final canEnterHomeScreen = await CaregiverApiService.instance
          .verifyOrLogoutIfMismatchedElder(currentElderId);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              canEnterHomeScreen ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
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
                  color: _isServerOnline
                      ? const Color(0xFF7A9850)
                      : const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  _isServerOnline
                      ? (ApiService.instance.activeServerUrl.contains(
                              '127.0.0.1',
                            )
                            ? 'Đã kết nối'
                            : (ApiService.instance.activeServerUrl.contains(
                                    'trycloudflare.com',
                                  ) ||
                                  ApiService.instance.activeServerUrl.contains(
                                    'azurewebsites.net',
                                  ) ||
                                  ApiService.instance.activeServerUrl
                                      .startsWith('https://'))
                            ? 'Đã kết nối'
                            : 'Đã kết nối')
                      : 'Đang ngoại tuyến',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: CareAiColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.swap_horiz_rounded,
              color: Color(0xFF456624),
            ),
            tooltip: 'Đổi vai trò Người thân',
            onPressed: _handleSwitchRole,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: _pendingPacketCount > 0,
              label: Text('$_pendingPacketCount'),
              child: const Icon(Icons.sync, color: CareAiColors.brown),
            ),
            tooltip: 'Đồng bộ ngoại tuyến',
            onPressed: _handleManualSync,
          ),
          IconButton(
            icon: const Icon(
              Icons.settings_outlined,
              color: CareAiColors.brown,
            ),
            tooltip: 'Cài đặt thiết bị',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            // Banner trạng thái SOS / Sự cố khẩn cấp (Phản hồi 2 chiều Closed-Loop)
            if (_isSosActive)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _activeIncidentStatus == 'ACKNOWLEDGED'
                      ? const Color(0xFFE2EDD3) // Xanh lục an tâm (Emerald 900)
                      : const Color(0xFFFFEDE7), // Đỏ cảnh báo (Red 900)
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _activeIncidentStatus == 'ACKNOWLEDGED'
                        ? const Color(0xFF456624) // Emerald 500
                        : const Color(0xFFEF4444), // Red 500
                    width: 1.5,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      _activeIncidentStatus == 'ACKNOWLEDGED'
                          ? Icons.check_circle_rounded
                          : Icons.notifications_active,
                      color: _activeIncidentStatus == 'ACKNOWLEDGED'
                          ? const Color(0xFF456624)
                          : CareAiColors.danger,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _activeIncidentStatus == 'ACKNOWLEDGED'
                                ? 'NGƯỜI THÂN ĐÃ TIẾP NHẬN!'
                                : 'ĐÃ PHÁT TÍN HIỆU CẤP CỨU',
                            style: const TextStyle(
                              color: CareAiColors.ink,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _activeIncidentStatus == 'ACKNOWLEDGED'
                                ? '${_acknowledgedByName ?? 'Người thân'} đã tiếp nhận${_acknowledgedAt != null ? ' lúc ${DateFormat('HH:mm').format(_acknowledgedAt!.toLocal())}' : ''}\n${_acknowledgedNote != null && _acknowledgedNote!.isNotEmpty ? _acknowledgedNote! : 'Đang đến hỗ trợ, ông/bà yên tâm nhé!'}'
                                : 'Mã: ${_lastSosPacketId ?? 'SOS'}\nĐang chờ người nhà tiếp nhận...',
                            style: TextStyle(
                              color: _activeIncidentStatus == 'ACKNOWLEDGED'
                                  ? const Color(0xFF456624)
                                  : CareAiColors.secondary,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: CareAiColors.secondary,
                      ),
                      tooltip: 'Đóng thông báo',
                      onPressed: () {
                        _stopIncidentPolling();
                        setState(() {
                          _isSosActive = false;
                          _activeIncidentStatus = null;
                        });
                        FallService.instance.stopEmergencySound();
                        FallService.instance.notifyIncidentStatusToWatch(
                          status: 'RESOLVED',
                        );
                      },
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  const Text(
                    'Cần người thân giúp?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: CareAiColors.ink,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    button: true,
                    label: 'SOS. Báo cần giúp cho người thân',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: CareAiColors.peach,
                        shape: BoxShape.circle,
                      ),
                      child: Material(
                        color: CareAiColors.danger,
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _triggerManualSos,
                          child: SizedBox(
                            width: 232,
                            height: 232,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'SOS',
                                  style: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    height: 1.15,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Chạm nút SOS để báo cần giúp.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: CareAiColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Bạn có thể hủy nếu chạm nhầm ở bước xác nhận.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: CareAiColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            // Thông tin hồ sơ và GPS nằm sau thao tác SOS chính.
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: CareAiColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 24,
                        backgroundColor: CareAiColors.peach,
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: CareAiColors.brown,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _elderName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: CareAiColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 20,
                        color: EmergencyEvidenceService.recentFix == null
                            ? CareAiColors.amber
                            : CareAiColors.greenInk,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _locatingGps
                              ? 'Đang tìm vị trí…'
                              : EmergencyEvidenceService.recentFix == null
                              ? 'Chưa có vị trí mới'
                              : 'Vị trí sẵn sàng gửi người thân',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: CareAiColors.secondary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cập nhật lại GPS',
                        onPressed: _locatingGps ? null : _prepareGps,
                        icon: _locatingGps
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.my_location_rounded,
                                color: CareAiColors.greenInk,
                              ),
                      ),
                    ],
                  ),
                  if (!_backgroundGpsGranted)
                    TextButton.icon(
                      onPressed: _enableBackgroundGps,
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('Bật vị trí khi ở nền'),
                    ),
                ],
              ),
            ),
            // Card Thiết bị đeo Galaxy Watch (Wear OS) / Apple Watch (watchOS)
            Builder(
              builder: (context) {
                final isConnected = _watchStatus.isConnected;
                final hasKnownWatch =
                    (_watchStatus.watchName != null &&
                        _watchStatus.watchName!.isNotEmpty) ||
                    (_lastPairedWatchName != null &&
                        _lastPairedWatchName!.isNotEmpty) ||
                    _customWatchAlias != null ||
                    _watchStatus.isPaired;
                final isBtOff =
                    !isConnected && _watchStatus.reason == 'BLUETOOTH_OFF';
                final isDisconnected = !isConnected && hasKnownWatch;
                final watchTitle = isConnected
                    ? _effectiveWatchDisplayName
                    : (isDisconnected
                          ? _effectiveWatchDisplayName
                          : 'Chưa ghép nối đồng hồ');

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
                      statusSubtext =
                          '🔋 Đã sạc đầy 100% · Nhớ đeo lại vào tay';
                      borderColor = const Color(0xFF456624)
                          .withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFFE2EDD3)
                          .withValues(alpha: 0.6);
                      iconColor = const Color(0xFF456624);
                      subtextColor = const Color(0xFF456624);
                      iconData = Icons.battery_charging_full_rounded;
                    } else {
                      final pctStr = batteryPct != null
                          ? ' ($batteryPct%)'
                          : '';
                      statusSubtext =
                          '⚡ Đang sạc pin$pctStr · Tạm dừng sinh hiệu';
                      borderColor = const Color(0xFF456624)
                          .withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFFF0F4E4)
                          .withValues(alpha: 0.6);
                      iconColor = const Color(0xFF456624);
                      subtextColor = const Color(0xFF456624);
                      iconData = Icons.battery_charging_full_rounded;
                    }
                  } else if (isWorn == false) {
                    final pctStr = batteryPct != null
                        ? ' · Pin $batteryPct%'
                        : '';
                    if (batteryPct != null && batteryPct <= 20) {
                      statusSubtext =
                          '⚠️ Đã tháo khỏi cổ tay · Pin yếu $batteryPct%';
                      borderColor = const Color(0xFFEF4444)
                          .withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFFFFEDE7)
                          .withValues(alpha: 0.6);
                      iconColor = const Color(0xFFC93B2B);
                      subtextColor = const Color(0xFFC93B2B);
                      iconData = Icons.battery_alert_rounded;
                    } else {
                      statusSubtext = '🟡 Đã tháo khỏi cổ tay$pctStr';
                      borderColor = const Color(0xFFF59E0B)
                          .withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFFFAEFE5)
                          .withValues(alpha: 0.6);
                      iconColor = const Color(0xFF916018);
                      subtextColor = const Color(0xFF916018);
                      iconData = Icons.watch_off_outlined;
                    }
                  } else {
                    if (batteryPct != null && batteryPct <= 10) {
                      statusSubtext =
                          '🚨 Pin đồng hồ sắp cạn ($batteryPct%) · Hãy sạc ngay';
                      borderColor = const Color(0xFFEF4444)
                          .withValues(alpha: 0.9);
                      iconBgColor = const Color(0xFFFFEDE7)
                          .withValues(alpha: 0.7);
                      iconColor = const Color(0xFFC93B2B);
                      subtextColor = const Color(0xFFC93B2B);
                      iconData = Icons.battery_alert_rounded;
                    } else if (batteryPct != null && batteryPct <= 20) {
                      statusSubtext =
                          '⚠️ Pin đồng hồ yếu ($batteryPct%) · Vui lòng cắm sạc';
                      borderColor = const Color(0xFFF59E0B)
                          .withValues(alpha: 0.8);
                      iconBgColor = const Color(0xFFFAEFE5)
                          .withValues(alpha: 0.6);
                      iconColor = const Color(0xFF916018);
                      subtextColor = const Color(0xFF916018);
                      iconData = Icons.battery_alert_rounded;
                    } else {
                      final pctStr = batteryPct != null
                          ? ' (Pin $batteryPct%)'
                          : '';
                      statusSubtext =
                          '🟢 Đã kết nối · Trên cổ tay$pctStr · $_platformSensorLabel';
                      borderColor = const Color(0xFF7A9850)
                          .withValues(alpha: 0.6);
                      iconBgColor = const Color(0xFFE2EDD3)
                          .withValues(alpha: 0.5);
                      iconColor = const Color(0xFF456624);
                      subtextColor = const Color(0xFF456624);
                      iconData = Icons.watch;
                    }
                  }
                } else if (isDisconnected) {
                  if (isBtOff) {
                    statusSubtext =
                        '🔴 Bluetooth đang tắt · Gạt bật để kết nối đồng hồ';
                    borderColor = const Color(0xFFEF4444)
                        .withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFFFFEDE7)
                        .withValues(alpha: 0.5);
                    iconColor = const Color(0xFFC93B2B);
                    subtextColor = const Color(0xFFC93B2B);
                    iconData = Icons.bluetooth_disabled_rounded;
                  } else if (_isDebouncingDisconnect) {
                    statusSubtext =
                        '🟡 Đang tìm lại đồng hồ (tạm xa điện thoại)';
                    borderColor = const Color(0xFFF59E0B)
                        .withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFFFAEFE5)
                        .withValues(alpha: 0.5);
                    iconColor = const Color(0xFF916018);
                    subtextColor = const Color(0xFF916018);
                    iconData = Icons.watch_later_outlined;
                  } else {
                    statusSubtext =
                        '🔴 Mất tín hiệu đồng hồ · Kiểm tra khoảng cách/Pin';
                    borderColor = const Color(0xFFEF4444)
                        .withValues(alpha: 0.7);
                    iconBgColor = const Color(0xFFFFEDE7)
                        .withValues(alpha: 0.5);
                    iconColor = const Color(0xFFC93B2B);
                    subtextColor = const Color(0xFFC93B2B);
                    iconData = Icons.watch_off_outlined;
                  }
                } else {
                  statusSubtext =
                      '⚪ $_platformWatchTitle (Chạm để quét & kiểm tra)';
                  borderColor = const Color(0xFF8C7A6B).withValues(alpha: 0.4);
                  iconBgColor = const Color(0xFFFFFFFF);
                  iconColor = const Color(0xFF7D7168);
                  subtextColor = const Color(0xFF7D7168);
                  iconData = Icons.watch;
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: isBtOff
                          ? _openBluetoothSettings
                          : () => _checkWatchStatus(showFeedback: true),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF7F2),
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
                              child: Icon(iconData, color: iconColor, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          watchTitle,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: CareAiColors.ink,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isConnected || hasKnownWatch) ...[
                                        const SizedBox(width: 6),
                                        GestureDetector(
                                          onTap: () => _showEditWatchNameDialog(
                                            watchTitle,
                                          ),
                                          child: const Padding(
                                            padding: EdgeInsets.all(2),
                                            child: Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                              color: Color(0xFF456624),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    statusSubtext,
                                    style: TextStyle(
                                      fontSize: 14,
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626)
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFEF4444),
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bluetooth_searching,
                                        size: 14,
                                        color: Color(0xFFC93B2B),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Bật BT',
                                        style: TextStyle(
                                          color: Color(0xFFC93B2B),
                                          fontSize: 14,
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
                                  color: Color(0xFF916018),
                                ),
                              )
                            else if (isConnected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF7A9850),
                                size: 18,
                              )
                            else
                              const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFF7D7168),
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
                            const Icon(
                              Icons.lightbulb_outline,
                              size: 13,
                              color: Color(0xFF916018),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Mẹo: Vuốt mép trên màn hình xuống & chạm icon Bluetooth để bật lại nhanh',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: const Color(0xFF916018)
                                      .withValues(alpha: 0.9),
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
          ],
        ),
      ),
      // Thanh trạng thái dưới cùng: Cố định 100% ở đáy màn hình bằng bottomNavigationBar (không bao giờ bị trôi/di chuyển)
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        color: const Color(0xFFFFFFFF),
        child: SafeArea(
          top: false,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_upload_outlined,
                    size: 18,
                    color: Color(0xFF7D7168),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _lastSyncTime != null
                          ? 'Đã đồng bộ: ${_lastSyncTime!.hour.toString().padLeft(2, '0')}:${_lastSyncTime!.minute.toString().padLeft(2, '0')}'
                          : 'Chưa có lượt đồng bộ',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7D7168),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.storage_outlined,
                    size: 18,
                    color: Color(0xFF7D7168),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '$_pendingPacketCount gói chờ',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF7D7168),
                      ),
                    ),
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
  State<_ManualSosConfirmDialog> createState() =>
      _ManualSosConfirmDialogState();
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
      backgroundColor: const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.crisis_alert, color: Color(0xFFEF4444)),
          SizedBox(width: 10),
          Text(
            'Xác Nhận Cấp Cứu',
            style: TextStyle(
              color: CareAiColors.ink,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Hệ thống sẽ tự động gửi tín hiệu khẩn cấp đến toàn bộ người thân trong:',
            style: TextStyle(color: Color(0xFF5C493B), fontSize: 14),
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
          const Text('giây', style: TextStyle(color: Color(0xFF7D7168))),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => _finish(false),
          child: const Text(
            'HỦY BỎ (CHẠM NHẦM)',
            style: TextStyle(color: CareAiColors.secondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => _finish(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
          ),
          child: const Text(
            'GỬI NGAY',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
