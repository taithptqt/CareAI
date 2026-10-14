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
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;
  bool _isActionTaken = false;
  late final Future<CurrentGpsFix?> _locationTask;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.event.secondsRemaining;
    _locationTask = EmergencyEvidenceService.captureCurrentLocation();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Kích hoạt hướng dẫn y tế bằng giọng nói tiếng Việt (Gói C - TTS 0ms offline)
    VoiceGuidanceService.instance.speakFallDetected();

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        _handleSendEmergencyNow();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    FallService.instance.stopEmergencySound(widget.event.eventId);
    VoiceGuidanceService.instance.stop();
    super.dispose();
  }

  Future<void> _handleUserIsOk() async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    _timer?.cancel();
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

  Future<void> _handleSendEmergencyNow() async {
    if (_isActionTaken) return;
    _isActionTaken = true;
    _timer?.cancel();
    VoiceGuidanceService.instance.stop();
    await FallService.instance.stopEmergencySound(widget.event.eventId);

    final canonicalPacketId = 'FALL_${widget.event.eventId}';

    final recentFix = EmergencyEvidenceService.recentFix;
    final initialGps = (recentFix != null && !recentFix.isSimulated) ? recentFix.coordinates : null;
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
    ];
    if (lastHr != null && lastHr > 0) {
      samples.add(TelemetrySample(
        metricType: 'HEART_RATE',
        value: lastHr,
        unit: 'bpm',
        timestamp: now,
      ));
    }
    if (lastSpo2 != null && lastSpo2 > 0) {
      samples.add(TelemetrySample(
        metricType: 'SPO2',
        value: lastSpo2,
        unit: '%',
        timestamp: now,
      ));
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

    // Ghi trước vào Outbox SQLite
    await LocalOfflineStore.instance.enqueuePacket(
      packetId: canonicalPacketId,
      packetType: 'FALL_ALERT',
      payload: jsonEncode(request.toJson()),
    );

    // Bắn Fast-Lane SOS
    try {
      final result = await ApiService.instance.sendFastLaneSosWithResult(request);
      if (result.accepted) {
        await LocalOfflineStore.instance.markPacketSynced(canonicalPacketId);
        if (result.incidentId != null) {
          unawaited(EmergencyEvidenceService.attachLocationWhenReady(
              result.incidentId!, _locationTask, initiallySentGps: initialGps));
          unawaited(EmergencyEvidenceService.captureAndUploadPhoto(result.incidentId!));
        }
      }
    } catch (_) {
      // Ngoại tuyến: Vẫn nằm an toàn trong SQLite Outbox
    }

    if (mounted) {
      widget.onEmergencyTriggered?.call(canonicalPacketId);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseColor = Color.lerp(
              const Color(0xFFEF4444),
              const Color(0xFF7F1D1D),
              _pulseController.value,
            )!;

            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: pulseColor, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: pulseColor.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFDC2626),
                  size: 54,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'PHÁT HIỆN TÉ NGÃ!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF991B1B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.event.isFromHardwareWatch
                    ? 'Cảm biến Galaxy Watch phát hiện cú ngã mạnh.'
                    : 'Cảm biến chuyển động điện thoại phát hiện va đập.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 24),

              // Đồng hồ đếm ngược to rõ
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFDC2626), width: 5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_remainingSeconds',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'giây nữa sẽ tự động gọi cấp cứu',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 28),

              // Nút TÔI ỔN (Chỉ cần 1 chạm)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleUserIsOk,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 26),
                      SizedBox(width: 8),
                      Text(
                        'TÔI ỔN - HỦY CẢNH BÁO',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Nút GỬI CẤP CỨU NGAY (Chỉ cần 1 chạm)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _handleSendEmergencyNow,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFDC2626), width: 2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'CẦN TRỢ GIÚP - GỬI NGAY',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
