import '../theme/careai_theme.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fall_event.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';
import '../services/api_service.dart';
import '../services/emergency_evidence_service.dart';
import '../services/fall_service.dart';
import '../services/local_offline_store.dart';
import '../services/voice_guidance_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class FallCountdownDialog extends StatefulWidget {
  final FallEvent event;
  final void Function(String packetId)? onEmergencyTriggered;

  const FallCountdownDialog({
    super.key,
    required this.event,
    this.onEmergencyTriggered,
  });

  @override
  State<FallCountdownDialog> createState() => _FallCountdownDialogState();
}

class _FallCountdownDialogState extends State<FallCountdownDialog>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late int _remainingSeconds;
  late final int _totalSeconds;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  late AnimationController _pulseController;
  bool _isActionTaken = false;
  late final Future<CurrentGpsFix?> _locationTask;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _totalSeconds = widget.event.secondsRemaining > 0
        ? widget.event.secondsRemaining
        : 30;
    _remainingSeconds = _totalSeconds;
    _stopwatch.start();
    _locationTask = EmergencyEvidenceService.captureCurrentLocation();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Kích hoạt hướng dẫn y tế bằng giọng nói tiếng Việt (Gói C - TTS 0ms offline)
    VoiceGuidanceService.instance.speakFallDetected();

    _startCountdown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isActionTaken) {
      final remaining = _totalSeconds - _stopwatch.elapsed.inSeconds;
      if (remaining <= 0) {
        _timer?.cancel();
        _handleSendEmergencyNow(isTimeout: true);
      } else if (remaining != _remainingSeconds && mounted) {
        setState(() {
          _remainingSeconds = remaining;
        });
      }
    }
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isActionTaken) {
        timer.cancel();
        return;
      }
      final remaining = _totalSeconds - _stopwatch.elapsed.inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        _handleSendEmergencyNow(isTimeout: true);
      } else if (remaining != _remainingSeconds) {
        HapticFeedback.vibrate();
        if (mounted) {
          setState(() {
            _remainingSeconds = remaining;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _stopwatch.stop();
    _pulseController.dispose();
    FallService.instance.stopEmergencySound(widget.event.eventId);
    VoiceGuidanceService.instance.stop();
    super.dispose();
  }

  Future<void> _handleUserIsOk() async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    _timer?.cancel();
    _stopwatch.stop();
    VoiceGuidanceService.instance.stop();

    await FallService.instance.cancelFallAlarm(widget.event.eventId);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy cảnh báo: Người dùng xác nhận bình an.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleSendEmergencyNow({bool isTimeout = false}) async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    _timer?.cancel();
    _stopwatch.stop();
    VoiceGuidanceService.instance.stop();
    unawaited(FallService.instance.stopEmergencySound(widget.event.eventId));

    final canonicalPacketId = widget.event.eventId.startsWith('FALL_')
        ? widget.event.eventId
        : 'FALL_${widget.event.eventId}';

    final recentFix = EmergencyEvidenceService.recentFix;
    final initialGps = (recentFix != null && !recentFix.isSimulated)
        ? recentFix.coordinates
        : null;
    final prefs = await SharedPreferences.getInstance();
    final lastHr = prefs.getDouble('careai_last_heart_rate');
    final lastSpo2 = prefs.getDouble('careai_last_spo2');
    final now = DateTime.now().toUtc();

    final samples = <TelemetrySample>[
      TelemetrySample(
        metricType: 'FALL',
        value: widget.event.impactG ?? 2.5,
        unit: 'G',
        timestamp: now,
      ),
      TelemetrySample(
        metricType: 'FALL_TRIGGER',
        value: isTimeout ? 0.0 : 1.0,
        unit: isTimeout ? 'TIMEOUT_NO_DISMISSAL' : 'MANUAL_CONFIRMED',
        timestamp: now,
      ),
    ];
    if (lastHr != null && lastHr > 0) {
      samples.add(
        TelemetrySample(
          metricType: 'HEART_RATE',
          value: lastHr,
          unit: 'bpm',
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

    // Fact 35 Invariant: Gói Fast-Lane SOS lưu toàn bộ mẫu đo sinh hiệu thực tế đi kèm (nếu có, không bịa đặt số liệu giả)
    final request = SosPacketRequest(
      packetId: canonicalPacketId,
      eventId: widget.event.eventId,
      emergencyType: 'FALL',
      severity: 'CRITICAL',
      triggeredAt: now,
      gpsLocation: initialGps,
      gpsIsSimulated: recentFix?.isSimulated,
      gpsAccuracyMeters: recentFix?.accuracyMeters,
      samples: samples,
    );

    // Ghi trước vào Outbox SQLite ngay lập tức
    await LocalOfflineStore.instance.enqueuePacket(
      packetId: canonicalPacketId,
      packetType: 'FALL_ALERT',
      payload: jsonEncode(request.toJson()),
    );

    // Thoát dialog ngay lập tức để chuyển sang màn hình cứu hộ SOS, không bắt người già chờ mạng
    if (mounted) {
      widget.onEmergencyTriggered?.call(canonicalPacketId);
      Navigator.of(context).pop();
    }

    // Bắn Fast-Lane SOS bất đồng bộ trong nền
    unawaited(() async {
      try {
        final result = await ApiService.instance.sendFastLaneSosWithResult(
          request,
        );
        if (result.accepted) {
          await LocalOfflineStore.instance.markPacketSynced(canonicalPacketId);
          if (result.incidentId != null) {
            unawaited(
              EmergencyEvidenceService.attachLocationWhenReady(
                result.incidentId!,
                _locationTask,
                initiallySentGps: initialGps,
              ),
            );
            unawaited(
              EmergencyEvidenceService.captureAndUploadPhoto(
                result.incidentId!,
              ),
            );
          }
        }
      } catch (_) {
        // Ngoại tuyến: Vẫn nằm an toàn trong SQLite Outbox
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: CareAiColors.canvas,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480,
            maxHeight: MediaQuery.sizeOf(context).height - 48,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!largeText)
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: CareAiColors.dangerSurface,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              size: 42,
                              color: CareAiColors.danger,
                            ),
                          ),
                        const SizedBox(height: 20),
                        const Text(
                          'Bạn vẫn ổn chứ?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 25,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: CareAiColors.ink,
                          ),
                        ),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: CareAiColors.dangerSurface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: reduceMotion
                                    ? CareAiColors.danger
                                    : Color.lerp(
                                        CareAiColors.danger,
                                        CareAiColors.coral,
                                        _pulseController.value,
                                      )!,
                                width: 2,
                              ),
                            ),
                            child: child,
                          ),
                          child: Semantics(
                            label:
                                'Còn $_remainingSeconds giây trước khi gửi SOS',
                            child: ExcludeSemantics(
                              child: Column(
                                children: [
                                  Text(
                                    '$_remainingSeconds',
                                    style: const TextStyle(
                                      fontSize: 48,
                                      height: 1.1,
                                      fontWeight: FontWeight.w800,
                                      color: CareAiColors.danger,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'giây trước khi gửi SOS',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: CareAiColors.brown,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.event.isFromHardwareWatch
                              ? 'Đồng hồ vừa ghi nhận dấu hiệu té ngã.'
                              : 'Điện thoại vừa ghi nhận va đập có thể do té ngã.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: CareAiColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Nếu bạn vẫn ổn, hãy hủy cảnh báo. Nếu cần giúp, gửi SOS ngay cho người thân.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: CareAiColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _handleUserIsOk,
                    style: FilledButton.styleFrom(
                      backgroundColor: CareAiColors.greenInk,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 64),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text(
                      'Tôi vẫn ổn',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleSendEmergencyNow(isTimeout: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CareAiColors.danger,
                      side: const BorderSide(color: CareAiColors.danger),
                      minimumSize: const Size(48, 60),
                    ),
                    icon: const Icon(Icons.sos_rounded),
                    label: const Text(
                      'Gửi SOS ngay',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
