import '../../theme/careai_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/location_service.dart';

import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import '../services/caregiver_push_service.dart';
import '../widgets/heart_rate_chart_widget.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Incident incident;
  final bool initialSilence;
  const IncidentDetailScreen({
    super.key,
    required this.incident,
    this.initialSilence = false,
  });

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen>
    with WidgetsBindingObserver {
  static const _alarm = MethodChannel('vn.careai.companion/caregiver_alarm');
  late Incident _incident;
  late bool _userSilenced;
  IncidentHeartRateWindow? _heartRateWindow;
  Uint8List? _photoBytes;
  bool _loadingPhoto = false;
  bool _isLoadingHeartRate = false;

  Timer? _refreshTimer;
  StreamSubscription<String>? _pushSubscription;
  bool _busy = false;
  bool _refreshing = false;
  bool _sounding = false;
  String? _contactNumber;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _incident = widget.incident;
    _userSilenced = widget.initialSilence;
    _heartRateWindow = widget.incident.heartRateSeries;
    CaregiverPushService.instance.visibleIncidentId = _incident.id;
    WidgetsBinding.instance.addObserver(this);
    _pushSubscription = CaregiverPushService.instance.incidentsChanged.listen((
      id,
    ) {
      if (id == _incident.id) unawaited(_refresh());
    });
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_refresh()),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refresh());
      unawaited(_loadContact());
      unawaited(_loadPhoto());
      if (_heartRateWindow == null) {
        unawaited(_loadHeartRateSeries());
      }
    });
  }

  bool get _urgent => _incident.isOpen && _incident.severity == 'Critical';

  Future<void> _syncAlarm() async {
    if (_userSilenced) {
      if (_sounding) await _stopAlarm();
      return;
    }
    if (_urgent == _sounding) return;
    try {
      await _alarm.invokeMethod<void>(_urgent ? 'start' : 'stop', {
        'incidentId': _incident.id,
        'alertCycleNumber': _incident.alertState?.cycleNumber ?? 1,
      });
      _sounding = _urgent;
    } on MissingPluginException {
      // Fallback khi chạy Flutter widget tests không có kênh native siren (iOS và Android đã hỗ trợ đầy đủ).
    } catch (error) {
      debugPrint('[CareAI] Không thể điều khiển còi: $error');
    }
  }

  Future<void> _stopAlarm() async {
    try {
      await _alarm.invokeMethod<void>('stop', {
        'incidentId': _incident.id,
        'alertCycleNumber': _incident.alertState?.cycleNumber ?? 1,
      });
    } catch (_) {}
    _sounding = false;
  }

  Future<void> _loadHeartRateSeries() async {
    if (_isLoadingHeartRate) return;
    _isLoadingHeartRate = true;
    try {
      final series = await CaregiverApiService.instance
          .getIncidentHeartRateSeries(_incident.id);
      if (mounted) setState(() => _heartRateWindow = series);
    } catch (error) {
      debugPrint('[CareAI] Tải chuỗi nhịp tim thất bại: $error');
    } finally {
      if (mounted) _isLoadingHeartRate = false;
    }
  }

  Future<void> _loadPhoto() async {
    if (_loadingPhoto || _photoBytes != null) return;
    _loadingPhoto = true;
    try {
      final bytes = await CaregiverApiService.instance.getIncidentPhoto(
        _incident.id,
      );
      if (mounted && bytes != null) setState(() => _photoBytes = bytes);
    } catch (error) {
      debugPrint('[CareAI] Không thể tải ảnh sự cố: $error');
    } finally {
      _loadingPhoto = false;
    }
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final incident = await CaregiverApiService.instance.getIncident(
        _incident.id,
      );
      if (!mounted) return;
      setState(() {
        _incident = incident;
        if (incident.heartRateSeries != null) {
          _heartRateWindow = incident.heartRateSeries;
        }
      });
      if (_heartRateWindow == null) {
        unawaited(_loadHeartRateSeries());
      }
      if (_photoBytes == null) unawaited(_loadPhoto());
      await _syncAlarm();
    } catch (error) {
      debugPrint('[CareAI] Tải lại sự cố thất bại: $error');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadContact() async {
    try {
      final elders = await CaregiverApiService.instance.getMyElders();
      for (final elder in elders) {
        if (elder.id == _incident.elderProfileId && mounted) {
          setState(() => _contactNumber = elder.emergencyContact?.trim());
          return;
        }
      }
    } catch (error) {
      debugPrint('[CareAI] Không thể tải số liên hệ: $error');
    }
  }

  Future<void> _dial(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được ứng dụng gọi điện.')),
      );
    }
  }

  Future<void> _acknowledge() async {
    setState(() => _busy = true);
    try {
      await CaregiverApiService.instance.acknowledgeIncident(_incident);
      await _stopAlarm();
      await HapticFeedback.lightImpact();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Đã tiếp nhận sự cố.')));
      }
    } catch (error) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tiếp nhận thất bại: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isStaleIncident {
    final upper = _incident.emergencyType.toUpperCase();
    return upper.contains('STALE') || upper.contains('OFFLINE');
  }

  Future<void> _resolve() async {
    final caregiverName = await CaregiverApiService.instance.getCaregiverName();
    final isTechnical = _isStaleIncident;

    String finalNotes;
    if (isTechnical) {
      // Hướng 1: 1-Tap Resolve cho sự cố kỹ thuật (mất tín hiệu, kết nối thiết bị)
      // Tự động giải quyết ngay 1 chạm, bỏ hoàn toàn popup hộp thoại giải quyết
      finalNotes = (caregiverName != null && caregiverName.trim().isNotEmpty)
          ? '$caregiverName đã kiểm tra kết nối thiết bị bình thường.'
          : 'Người thân đã kiểm tra kết nối thiết bị bình thường.';
    } else {
      final defaultNote =
          (caregiverName != null && caregiverName.trim().isNotEmpty)
          ? '$caregiverName đã tiếp nhận và hỗ trợ an toàn.'
          : 'Người thân đã tiếp nhận và hỗ trợ an toàn.';
      _notes.text = defaultNote;

      final quickChips = [
        'Cụ đã an toàn',
        'Báo động nhầm / Cụ ổn',
        'Đang có mặt hỗ trợ',
        'Đã liên hệ 115',
      ];

      if (!mounted) return;
      final notes = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Giải quyết sự cố'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn nhanh lý do hoặc bấm xác nhận để đóng sự cố:',
                    style: TextStyle(fontSize: 13, color: Color(0xFF7D7168)),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickChips.map((chip) {
                      final isSelected = _notes.text == chip;
                      return ActionChip(
                        backgroundColor: isSelected
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFFF2ECE4),
                        side: BorderSide(
                          color: isSelected
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE4DACD),
                        ),
                        label: Text(
                          chip,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? const Color(0xFF15803D)
                                : const Color(0xFF5C493B),
                          ),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            _notes.text = chip;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Nội dung xử lý (đã điền sẵn)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text(
                  'Hủy',
                  style: TextStyle(color: Color(0xFF7D7168)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  final trimmed = _notes.text.trim();
                  Navigator.pop(
                    dialogContext,
                    trimmed.isEmpty ? defaultNote : trimmed,
                  );
                },
                child: const Text('Xác nhận Giải Quyết'),
              ),
            ],
          ),
        ),
      );
      if (notes == null || !mounted) return;
      finalNotes = notes.trim().isEmpty ? defaultNote : notes.trim();
    }

    setState(() => _busy = true);
    try {
      await CaregiverApiService.instance.resolveIncident(_incident, finalNotes);
      await _stopAlarm();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isTechnical
                  ? 'Đã giải quyết sự cố mất tín hiệu: Kết nối thiết bị bình thường.'
                  : 'Đã giải quyết sự cố thành công.',
            ),
          ),
        );
      }
    } catch (error) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Giải quyết thất bại: $error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _pushSubscription?.cancel();
    CaregiverPushService.instance.visibleIncidentId = null;
    _notes.dispose();
    super.dispose();
  }

  String _metric(double? value, String unit) => value == null
      ? 'Chưa có dữ liệu'
      : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit';

  Widget _row(String label, String? value) {
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 20;
    final labelText = Text(
      label,
      style: const TextStyle(color: CareAiColors.secondary),
    );
    final valueText = Text(
      value?.isNotEmpty == true ? value! : 'Chưa có dữ liệu',
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: const TextStyle(fontWeight: FontWeight.w600),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), valueText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: labelText),
                const SizedBox(width: 12),
                Expanded(child: valueText),
              ],
            ),
    );
  }

  IconData _emergencyIcon(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return Icons.warning_rounded;
    if (upper.contains('OXYGEN') || upper.contains('SPO2'))
      return Icons.air_rounded;
    if (upper.contains('TACHYCARDIA') ||
        upper.contains('BRADYCARDIA') ||
        upper.contains('SURGE') ||
        upper.contains('HR') ||
        upper.contains('HEART'))
      return Icons.monitor_heart_rounded;
    if (upper.contains('HYPERTENSION') || upper.contains('BLOOD_PRESSURE'))
      return Icons.speed_rounded;
    if (upper.contains('STALE') || upper.contains('OFFLINE'))
      return Icons.wifi_off_rounded;
    if (upper.contains('SOS')) return Icons.emergency_rounded;
    return Icons.warning_amber_rounded;
  }

  String _emergencyLabel(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return 'Té ngã';
    if (upper.contains('LOW_OXYGEN') ||
        upper.contains('LOWOXYGEN') ||
        upper.contains('OXYGEN'))
      return 'Oxy máu (SpO₂) thấp';
    if (upper.contains('TACHYCARDIA')) return 'Nhịp tim quá nhanh';
    if (upper.contains('BRADYCARDIA')) return 'Nhịp tim quá chậm';
    if (upper.contains('SURGE')) return 'Nhịp tim tăng đột biến';
    if (upper.contains('HYPERTENSION')) return 'Cơn tăng huyết áp';
    if (upper.contains('STALE') || upper.contains('OFFLINE'))
      return 'Mất tín hiệu thiết bị';
    if (upper.contains('SOS')) return 'Nút khẩn cấp SOS';
    return type;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'OPEN':
        return 'Đang mở';
      case 'ACKNOWLEDGED':
        return 'Đã tiếp nhận';
      case 'RESOLVED':
        return 'Đã giải quyết';
      default:
        return status;
    }
  }

  String _severityLabel(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return 'Nguy kịch';
      case 'HIGH':
        return 'Cao';
      case 'MEDIUM':
        return 'Trung bình';
      case 'LOW':
        return 'Thấp';
      default:
        return severity;
    }
  }

  List<IncidentTimeline> get _sortedTimeline {
    final list = List<IncidentTimeline>.from(_incident.timeline);
    list.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _incident.snapshot;
    final rescueGps = snapshot?.currentGpsLocation ?? snapshot?.gpsLocation;
    final isResolved = _incident.isResolved;
    final isAck = _incident.isAcknowledged;
    final alertState = _incident.alertState;

    final type = _incident.emergencyType.toUpperCase();
    final isStaleIncident = type.contains('STALE') || type.contains('OFFLINE');
    final isVitalIncident =
        type.contains('OXYGEN') ||
        type.contains('SPO2') ||
        type.contains('TACHYCARDIA') ||
        type.contains('BRADYCARDIA') ||
        type.contains('SURGE') ||
        type.contains('HYPERTENSION');

    Color appBarColor;
    if (isResolved) {
      appBarColor = const Color(0xFF0F766E);
    } else if (isAck) {
      appBarColor = Colors.amber.shade800;
    } else if (_urgent) {
      appBarColor = Colors.red.shade700;
    } else if (isStaleIncident) {
      appBarColor = const Color(0xFFD97706);
    } else if (isVitalIncident) {
      appBarColor = const Color(0xFFEA580C);
    } else {
      appBarColor = const Color(0xFF4A3020);
    }

    final String appBarTitle;
    if (isResolved) {
      appBarTitle = 'Chi tiết sự cố đã đóng';
    } else if (isStaleIncident) {
      appBarTitle = 'Chi tiết mất tín hiệu thiết bị';
    } else if (isVitalIncident) {
      appBarTitle = 'Chi tiết cảnh báo sinh hiệu';
    } else {
      appBarTitle = 'Cứu hộ khẩn cấp';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: CareAiColors.canvas,
        foregroundColor: CareAiColors.ink,
        actions: [
          if (_urgent)
            IconButton(
              icon: Icon(
                _userSilenced
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
              ),
              tooltip: _userSilenced ? 'Bật lại còi hú' : 'Tắt còi hú',
              onPressed: () async {
                setState(() {
                  _userSilenced = !_userSilenced;
                });
                if (_userSilenced) {
                  await _stopAlarm();
                } else {
                  await _syncAlarm();
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _refresh,
          ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomActionBar(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: isResolved
                  ? CareAiColors.greenSurface
                  : _urgent
                  ? CareAiColors.dangerSurface
                  : CareAiColors.peach,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _emergencyIcon(_incident.emergencyType),
                          color: appBarColor,
                          size: 26,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusLabel(_incident.status),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: appBarColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _incident.elderName,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _emergencyLabel(_incident.emergencyType),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: CareAiColors.brown,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          DateFormat('HH:mm · dd/MM/yyyy')
                              .format(_incident.triggeredAt.toLocal()),
                          style: const TextStyle(
                            fontSize: 13,
                            color: CareAiColors.secondary,
                          ),
                        ),
                        Text(
                          'Mức ${_severityLabel(_incident.severity)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: CareAiColors.brown,
                          ),
                        ),
                      ],
                    ),
                    if (_urgent || (isStaleIncident && !isResolved)) ...[
                      const SizedBox(height: 16),
                      Text(
                        _urgent
                            ? 'Cần người thân tiếp nhận ngay.'
                            : 'Cần kiểm tra kết nối thiết bị.',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: appBarColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _contactNumber?.isNotEmpty == true
                            ? () => _dial(_contactNumber!)
                            : null,
                        icon: const Icon(Icons.phone_outlined, size: 20),
                        label: Text(
                          _contactNumber?.isNotEmpty == true
                              ? 'Gọi người cao tuổi'
                              : 'Chưa có số liên hệ',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Banner Cảnh báo Tái mở / Nhắc nhở SLA (nếu có)
            if (alertState != null && alertState.cycleNumber > 1) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.sync_problem,
                      color: Color(0xFFD97706),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cảnh Báo Tái Mở / Nhắc Lại (Chu kỳ ${alertState.cycleNumber})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF92400E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Sự cố đã được nhắc lại do vượt quá thời hạn SLA hoặc tái mở do nhịp tim xấu đi sau khi tiếp nhận.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 3. Thông tin Tiếp nhận (nếu có)
            if (_incident.acknowledgedAt != null) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Color(0xFFD97706),
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Thông tin tiếp nhận',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      _row(
                        'Thời điểm tiếp nhận',
                        DateFormat('HH:mm:ss dd/MM/yyyy')
                            .format(_incident.acknowledgedAt!.toLocal()),
                      ),
                      if (_incident.acknowledgedByCaregiverId != null)
                        _row(
                          'Mã người thân tiếp nhận',
                          _incident.acknowledgedByCaregiverId,
                        ),
                      if (!isResolved) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Color(0xFF16A34A),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Ưu tiên hỗ trợ, chăm sóc cụ trước. Bạn không bắt buộc phải đóng sự cố ngay lúc này. Khi cụ đã an toàn và ổn định, hãy bấm "Giải quyết sự cố" bên dưới.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF15803D),
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 4. Thông tin Giải Quyết (nếu có)
            if (isResolved && _incident.resolvedAt != null) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: const Color(0xFFF0FDF4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.verified,
                            color: Color(0xFF16A34A),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Thông tin giải quyết',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF14532D),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      _row(
                        'Thời điểm giải quyết',
                        DateFormat('HH:mm:ss dd/MM/yyyy')
                            .format(_incident.resolvedAt!.toLocal()),
                      ),
                      if (_incident.resolvedByCaregiverId != null)
                        _row(
                          'Mã người giải quyết',
                          _incident.resolvedByCaregiverId,
                        ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ghi chú lâm sàng giải quyết:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF166534),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Text(
                          _incident.resolutionNotes?.isNotEmpty == true
                              ? _incident.resolutionNotes!
                              : '(Không có ghi chú)',
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF4A3020),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 5. Sinh hiệu khi xảy ra sự cố (Snapshot)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sinh hiệu khi xảy ra sự cố',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Divider(height: 16),
                    _row('Nhịp tim', _metric(snapshot?.heartRateBpm, 'bpm')),
                    _row('SpO₂', _metric(snapshot?.spO2Percent, '%')),
                    _row(
                      'Huyết áp tâm thu',
                      _metric(snapshot?.bpSystolic, 'mmHg'),
                    ),
                    _row(
                      'Huyết áp tâm trương',
                      _metric(snapshot?.bpDiastolic, 'mmHg'),
                    ),
                    _row(
                      'Đo lúc',
                      snapshot?.vitalsMeasuredAt == null
                          ? null
                          : DateFormat('HH:mm:ss dd/MM/yyyy')
                                .format(snapshot!.vitalsMeasuredAt!.toLocal()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 6. Vị trí cứu hộ
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Vị trí cứu hộ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Divider(height: 16),
                    _row(
                      snapshot?.currentGpsIsSimulated == true
                          ? 'GPS MÔ PHỎNG'
                          : 'GPS mới nhất',
                      rescueGps ??
                          'Chưa nhận được GPS từ điện thoại người cao tuổi',
                    ),
                    if (snapshot?.currentGpsIsSimulated == true)
                      const Text(
                        'Vị trí do emulator hoặc ứng dụng mô phỏng cung cấp; không phải vị trí thật của người cao tuổi.',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (snapshot?.currentGpsAccuracyMeters != null)
                      _row(
                        'Sai số ước tính',
                        '±${snapshot!.currentGpsAccuracyMeters!.round()} m',
                      ),
                    if (snapshot?.currentGpsMeasuredAt != null)
                      _row(
                        'Đo lúc',
                        DateFormat('HH:mm:ss dd/MM/yyyy')
                            .format(snapshot!.currentGpsMeasuredAt!.toLocal()),
                      ),
                    if (snapshot?.gpsLocation != null &&
                        snapshot?.gpsLocation != rescueGps)
                      _row('GPS lúc đầu', snapshot?.gpsLocation),
                    if (rescueGps != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A3020),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text(
                            'CHỈ ĐƯỜNG ĐẾN VỊ TRÍ CỤ (GPS)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          onPressed: () {
                            final parts = rescueGps.split(',');
                            if (parts.length == 2) {
                              final lat = double.tryParse(parts[0].trim());
                              final lng = double.tryParse(parts[1].trim());
                              if (lat != null && lng != null) {
                                LocationService.instance
                                    .openGoogleMapsDirections(lat, lng);
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    _row('Địa chỉ nhà', snapshot?.homeAddress),
                    if (snapshot?.homeAddress != null &&
                        snapshot!.homeAddress!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (rescueGps == null)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F766E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.home_rounded, size: 18),
                            label: const Text(
                              'CHỈ ĐƯỜNG ĐẾN NHÀ CỤ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            onPressed: () => LocationService.instance
                                .openDirectionsToAddress(snapshot.homeAddress!),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF0F766E),
                            ),
                            icon: const Icon(
                              Icons.directions_car_rounded,
                              size: 16,
                            ),
                            label: const Text(
                              'Chỉ đường về nhà',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () => LocationService.instance
                                .openDirectionsToAddress(snapshot.homeAddress!),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 7. Biểu Đồ Nhịp Tim T-15..T+15 Phút
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ảnh hiện trường sự cố',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_photoBytes == null)
                      const Text(
                        'Chưa có ảnh. Ảnh sẽ xuất hiện nếu điện thoại của người cao tuổi được cấp quyền camera và đang mở ứng dụng.',
                        style: TextStyle(color: Color(0xFF7D7168)),
                      )
                    else
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(_photoBytes!, fit: BoxFit.contain),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            HeartRateChartWidget(
              window: _heartRateWindow,
              incidentTriggeredAt: _incident.triggeredAt,
              snapshotHeartRate: snapshot?.heartRateBpm,
            ),
            const SizedBox(height: 16),

            // 9. Dòng thời gian chi tiết (Timeline Events)
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        const Text(
                          'Dòng thời gian sự kiện',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${_sortedTimeline.length} mốc',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7D7168),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_sortedTimeline.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Chưa có sự kiện nào được ghi nhận.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ..._sortedTimeline.map(
                        (event) => _buildTimelineItem(event),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  Widget? _buildStickyBottomActionBar() {
    if (_incident.isResolved) return null;

    final isAck = _incident.isAcknowledged;
    final primaryBgColor = isAck ? CareAiColors.greenInk : CareAiColors.brown;
    final primaryIcon = isAck ? Icons.task_alt : Icons.check_circle;
    final primaryLabel = isAck ? 'Giải quyết sự cố' : 'Tiếp nhận sự cố';
    final primaryAction = isAck ? _resolve : _acknowledge;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: CareAiColors.brown.withValues(alpha: 0.05),
            offset: const Offset(0, -3),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = MediaQuery.textScalerOf(context).scale(14) > 20;
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) * 0.4,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(
                          color: Color(0xFFDC2626),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => _dial('115'),
                      icon: const Icon(
                        Icons.emergency,
                        color: Color(0xFFDC2626),
                        size: 18,
                      ),
                      label: const Text(
                        'Gọi 115',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Color(0xFFDC2626),
                        ),
                        softWrap: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: stacked
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 10) * 0.6,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: primaryBgColor,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _busy ? null : primaryAction,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(primaryIcon, size: 18),
                      label: Text(
                        primaryLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineItem(IncidentTimeline event) {
    IconData iconData = Icons.circle;
    Color iconColor = const Color(0xFF7D7168);

    final type = event.eventType.toUpperCase();
    if (type.contains('CRITICAL') ||
        type.contains('SOS') ||
        type.contains('FALL') ||
        type.contains('CREATED')) {
      iconData = Icons.warning_amber_rounded;
      iconColor = const Color(0xFFDC2626);
    } else if (type.contains('ACK')) {
      iconData = Icons.check_circle;
      iconColor = const Color(0xFFD97706);
    } else if (type.contains('RESOLVE')) {
      iconData = Icons.verified;
      iconColor = const Color(0xFF16A34A);
    } else if (type.contains('NOTIF') || type.contains('FCM')) {
      iconData = Icons.notifications_active;
      iconColor = const Color(0xFF4A3020);
    } else if (type.contains('SLA') || type.contains('REMIND')) {
      iconData = Icons.timer_outlined;
      iconColor = const Color(0xFFEA580C);
    } else if (type.contains('ESCALAT') || type.contains('REOPEN')) {
      iconData = Icons.sync_problem;
      iconColor = const Color(0xFFDC2626);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(iconData, size: 14, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A3020),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('HH:mm:ss dd/MM/yyyy')
                      .format(event.recordedAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF7D7168),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
