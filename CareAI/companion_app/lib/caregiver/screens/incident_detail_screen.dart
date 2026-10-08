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
  const IncidentDetailScreen({super.key, required this.incident});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> with WidgetsBindingObserver {
  static const _alarm = MethodChannel('vn.careai.companion/caregiver_alarm');
  late Incident _incident;
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
    _heartRateWindow = widget.incident.heartRateSeries;
    CaregiverPushService.instance.visibleIncidentId = _incident.id;
    WidgetsBinding.instance.addObserver(this);
    _pushSubscription = CaregiverPushService.instance.incidentsChanged.listen((id) {
      if (id == _incident.id) unawaited(_refresh());
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(_refresh()));
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
    if (_urgent == _sounding) return;
    try {
      await _alarm.invokeMethod<void>(_urgent ? 'start' : 'stop', {
        'incidentId': _incident.id,
        'alertCycleNumber': _incident.alertState?.cycleNumber ?? 1,
      });
      _sounding = _urgent;
    } on MissingPluginException {
      // Widget tests and non-Android platforms have no native alarm channel.
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
      final series = await CaregiverApiService.instance.getIncidentHeartRateSeries(_incident.id);
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
      final bytes = await CaregiverApiService.instance.getIncidentPhoto(_incident.id);
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
      final incident = await CaregiverApiService.instance.getIncident(_incident.id);
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
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được ứng dụng gọi điện.')),
      );
    }
  }

  Future<void> _openGps(String coordinates) async {
    final uri = Uri.https('www.google.com', '/maps/search/',
        {'api': '1', 'query': coordinates});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không mở được bản đồ.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tiếp nhận sự cố.')),
        );
      }
    } catch (error) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tiếp nhận thất bại: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resolve() async {
    _notes.clear();
    final notes = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Giải quyết sự cố'),
        content: TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Ghi chú lâm sàng bắt buộc *',
            hintText: 'VD: Cụ đã an toàn, huyết áp đo lại bình thường...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _notes.text.trim()),
            child: const Text('Xác nhận Giải Quyết'),
          ),
        ],
      ),
    );
    if (notes == null || !mounted) return;
    if (notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập ghi chú lâm sàng để đóng sự cố.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await CaregiverApiService.instance.resolveIncident(_incident, notes);
      await _stopAlarm();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã giải quyết sự cố thành công.')),
        );
      }
    } catch (error) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Giải quyết thất bại: $error')),
        );
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

  String _metric(double? value, String unit) =>
      value == null ? 'Chưa có dữ liệu' : '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} $unit';

  Widget _row(String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
      Expanded(child: Text(value?.isNotEmpty == true ? value! : 'Chưa có dữ liệu',
        textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  IconData _emergencyIcon(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return Icons.warning_rounded;
    if (upper.contains('OXYGEN') || upper.contains('SPO2')) return Icons.air_rounded;
    if (upper.contains('TACHYCARDIA') || upper.contains('BRADYCARDIA') || upper.contains('SURGE') || upper.contains('HR') || upper.contains('HEART')) return Icons.monitor_heart_rounded;
    if (upper.contains('HYPERTENSION') || upper.contains('BLOOD_PRESSURE')) return Icons.speed_rounded;
    if (upper.contains('STALE') || upper.contains('OFFLINE')) return Icons.wifi_off_rounded;
    if (upper.contains('SOS')) return Icons.emergency_rounded;
    return Icons.warning_amber_rounded;
  }

  String _emergencyLabel(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return 'Té ngã';
    if (upper.contains('LOW_OXYGEN') || upper.contains('LOWOXYGEN') || upper.contains('OXYGEN')) return 'Oxy máu (SpO₂) thấp';
    if (upper.contains('TACHYCARDIA')) return 'Nhịp tim quá nhanh';
    if (upper.contains('BRADYCARDIA')) return 'Nhịp tim quá chậm';
    if (upper.contains('SURGE')) return 'Nhịp tim tăng đột biến';
    if (upper.contains('HYPERTENSION')) return 'Cơn tăng huyết áp';
    if (upper.contains('STALE') || upper.contains('OFFLINE')) return 'Mất tín hiệu thiết bị';
    if (upper.contains('SOS')) return 'Nút khẩn cấp SOS';
    return type;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'OPEN': return 'Đang mở';
      case 'ACKNOWLEDGED': return 'Đã tiếp nhận';
      case 'RESOLVED': return 'Đã giải quyết';
      default: return status;
    }
  }

  String _severityLabel(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL': return 'Nguy kịch';
      case 'HIGH': return 'Cao';
      case 'MEDIUM': return 'Trung bình';
      case 'LOW': return 'Thấp';
      default: return severity;
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

    Color appBarColor;
    if (_urgent) {
      appBarColor = Colors.red.shade700;
    } else if (isResolved) {
      appBarColor = const Color(0xFF0F766E);
    } else if (isAck) {
      appBarColor = Colors.amber.shade800;
    } else {
      appBarColor = const Color(0xFF0284C7);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isResolved ? 'Chi tiết sự cố đã đóng' : 'Cứu hộ khẩn cấp'),
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _refresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 1. Thẻ Tiêu đề Sự Cố
            Card(
              color: _urgent ? Colors.red.shade50 : (isResolved ? const Color(0xFFF0FDF4) : Colors.orange.shade50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      _emergencyIcon(_incident.emergencyType),
                      color: _urgent ? Colors.red.shade700 : (isResolved ? const Color(0xFF16A34A) : Colors.orange.shade800),
                      size: 44,
                    ),
                    const SizedBox(height: 8),
                    Text(_incident.elderName, style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${_emergencyLabel(_incident.emergencyType)} · Mức ${_severityLabel(_incident.severity)} · ${_statusLabel(_incident.status)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('HH:mm:ss dd/MM/yyyy').format(_incident.triggeredAt.toLocal()),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    if (_urgent) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'CẦN TIẾP NHẬN NGAY',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

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
                    const Icon(Icons.sync_problem, color: Color(0xFFD97706), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cảnh Báo Tái Mở / Nhắc Lại (Chu kỳ ${alertState.cycleNumber})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Sự cố đã được nhắc lại do vượt quá thời hạn SLA hoặc tái mở do nhịp tim xấu đi sau khi tiếp nhận.',
                            style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFFD97706), size: 18),
                          SizedBox(width: 8),
                          Text('Thông Tin Tiếp Nhận (ACK)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      const Divider(height: 16),
                      _row('Thời điểm tiếp nhận', DateFormat('HH:mm:ss dd/MM/yyyy').format(_incident.acknowledgedAt!.toLocal())),
                      if (_incident.acknowledgedByCaregiverId != null)
                        _row('Mã người thân tiếp nhận', _incident.acknowledgedByCaregiverId),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 4. Thông tin Giải Quyết (nếu có)
            if (isResolved && _incident.resolvedAt != null) ...[
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                color: const Color(0xFFF0FDF4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.verified, color: Color(0xFF16A34A), size: 20),
                          SizedBox(width: 8),
                          Text('Thông Tin Đóng Sự Cố (Resolved)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF14532D))),
                        ],
                      ),
                      const Divider(height: 16),
                      _row('Thời điểm giải quyết', DateFormat('HH:mm:ss dd/MM/yyyy').format(_incident.resolvedAt!.toLocal())),
                      if (_incident.resolvedByCaregiverId != null)
                        _row('Mã người giải quyết', _incident.resolvedByCaregiverId),
                      const SizedBox(height: 8),
                      const Text('Ghi chú lâm sàng giải quyết:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF166534))),
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
                          style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Color(0xFF1E293B)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sinh hiệu khi xảy ra sự cố', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Divider(height: 16),
                    _row('Nhịp tim', _metric(snapshot?.heartRateBpm, 'bpm')),
                    _row('SpO₂', _metric(snapshot?.spO2Percent, '%')),
                    _row('Huyết áp tâm thu', _metric(snapshot?.bpSystolic, 'mmHg')),
                    _row('Huyết áp tâm trương', _metric(snapshot?.bpDiastolic, 'mmHg')),
                    _row(
                      'Đo lúc',
                      snapshot?.vitalsMeasuredAt == null
                          ? null
                          : DateFormat('HH:mm:ss dd/MM/yyyy').format(snapshot!.vitalsMeasuredAt!.toLocal()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 6. Vị trí cứu hộ
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vị trí cứu hộ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const Divider(height: 16),
                    _row(snapshot?.currentGpsIsSimulated == true
                            ? 'GPS MÔ PHỎNG'
                            : 'GPS mới nhất', rescueGps ??
                        'Chưa nhận được GPS từ điện thoại cụ'),
                    if (snapshot?.currentGpsIsSimulated == true)
                      const Text('Vị trí do emulator hoặc ứng dụng mô phỏng cung cấp; không phải vị trí thật của cụ.',
                        style: TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600)),
                    if (snapshot?.currentGpsAccuracyMeters != null)
                      _row('Sai số ước tính',
                        '±${snapshot!.currentGpsAccuracyMeters!.round()} m'),
                    if (snapshot?.currentGpsMeasuredAt != null)
                      _row('Đo lúc', DateFormat('HH:mm:ss dd/MM/yyyy').format(
                          snapshot!.currentGpsMeasuredAt!.toLocal())),
                    if (snapshot?.gpsLocation != null &&
                        snapshot?.gpsLocation != rescueGps)
                      _row('GPS lúc đầu', snapshot?.gpsLocation),
                    if (rescueGps != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.map_rounded, size: 16),
                              label: const Text('Mở Bản Đồ Google', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () => _openGps(rescueGps),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0284C7),
                                side: const BorderSide(color: Color(0xFF0284C7)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.directions_rounded, size: 16),
                              label: const Text('Chỉ Đường Cấp Cứu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              onPressed: () {
                                final parts = rescueGps.split(',');
                                if (parts.length == 2) {
                                  final lat = double.tryParse(parts[0].trim());
                                  final lng = double.tryParse(parts[1].trim());
                                  if (lat != null && lng != null) {
                                    LocationService.instance.openGoogleMapsDirections(lat, lng);
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    _row('Địa chỉ nhà', snapshot?.homeAddress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 7. Biểu Đồ Nhịp Tim T-15..T+15 Phút
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ảnh hiện trường sự cố', style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (_photoBytes == null)
                    const Text('Chưa có ảnh. Ảnh sẽ xuất hiện nếu điện thoại của cụ được cấp quyền camera và đang mở ứng dụng.',
                      style: TextStyle(color: Color(0xFF64748B)))
                  else
                    ClipRRect(borderRadius: BorderRadius.circular(10),
                      child: Image.memory(_photoBytes!, fit: BoxFit.contain)),
                ]),
              ),
            ),
            const SizedBox(height: 12),

            HeartRateChartWidget(
              window: _heartRateWindow,
              incidentTriggeredAt: _incident.triggeredAt,
              snapshotHeartRate: snapshot?.heartRateBpm,
            ),
            const SizedBox(height: 16),

            // 8. Các nút hành động khẩn cấp
            FilledButton.icon(
              onPressed: _contactNumber?.isNotEmpty == true ? () => _dial(_contactNumber!) : null,
              icon: const Icon(Icons.phone),
              label: Text(
                _contactNumber?.isNotEmpty == true
                    ? 'Gọi số liên hệ của cụ: $_contactNumber'
                    : 'Chưa có số liên hệ của cụ',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _dial('115'),
              icon: const Icon(Icons.emergency, color: Color(0xFFDC2626)),
              label: const Text('Gọi cấp cứu 115', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
            ),
            if (_incident.isOpen) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _busy ? null : _acknowledge,
                icon: const Icon(Icons.check_circle),
                label: const Text('Tiếp nhận sự cố (Acknowledge)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
            if (_incident.isAcknowledged) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _busy ? null : _resolve,
                icon: const Icon(Icons.task_alt),
                label: const Text('Giải quyết sự cố (Resolve)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
            const SizedBox(height: 20),

            // 9. Dòng thời gian chi tiết (Timeline Events)
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Dòng thời gian sự kiện', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text('${_sortedTimeline.length} mốc', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_sortedTimeline.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Chưa có sự kiện nào được ghi nhận.', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ..._sortedTimeline.map((event) => _buildTimelineItem(event)),
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

  Widget _buildTimelineItem(IncidentTimeline event) {
    IconData iconData = Icons.circle;
    Color iconColor = const Color(0xFF64748B);

    final type = event.eventType.toUpperCase();
    if (type.contains('CRITICAL') || type.contains('SOS') || type.contains('FALL') || type.contains('CREATED')) {
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
      iconColor = const Color(0xFF0284C7);
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('HH:mm:ss dd/MM/yyyy').format(event.recordedAt.toLocal()),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
