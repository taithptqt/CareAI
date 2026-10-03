import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../services/location_service.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import 'incident_detail_screen.dart';
import 'incident_history_screen.dart';
import 'health_corner_screen.dart';

class ElderDashboardScreen extends StatefulWidget {
  final String elderProfileId;
  final String elderName;

  const ElderDashboardScreen({
    super.key,
    required this.elderProfileId,
    required this.elderName,
  });

  @override
  State<ElderDashboardScreen> createState() => _ElderDashboardScreenState();
}

class _ElderDashboardScreenState extends State<ElderDashboardScreen> with WidgetsBindingObserver {
  ElderDashboard? _dashboard;
  HeartRate24hData? _heartRate24h;
  ThresholdData? _thresholdData;
  BloodPressureHistoryData? _bloodPressureHistory;
  Spo224hData? _spo224h;
  HourlyStepsData? _hourlySteps24h;
  SleepSummaryData? _sleepSummary;
  int _selectedChartTab = 0; // 0: HeartRate, 1: BloodPressure, 2: SpO2, 3: HourlySteps
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _vitalsRefreshTimer;
  bool _refreshingVitals = false;

  // Trạng thái mã PIN
  String? _generatedPin;
  DateTime? _pinExpiresAt;
  bool _isGeneratingPin = false;

  // Trạng thái phân tích AI
  bool _isAnalyzingThresholds = false;

  // Trạng thái mở rộng nhận định cho gia đình
  bool _isAdviceExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboard();
    _vitalsRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshLiveVitals(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vitalsRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLiveVitals());
    }
  }

  Future<void> _refreshLiveVitals() async {
    if (!mounted || _isLoading || _refreshingVitals) return;
    _refreshingVitals = true;
    try {
      final results = await Future.wait<Object>([
        CaregiverApiService.instance.getElderDashboard(widget.elderProfileId),
        CaregiverApiService.instance.getHeartRate24h(widget.elderProfileId),
        CaregiverApiService.instance.getSpo224h(widget.elderProfileId),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as ElderDashboard;
        _heartRate24h = results[1] as HeartRate24hData;
        _spo224h = results[2] as Spo224hData;
      });
    } catch (_) {
      // Keep the last received measurements and their timestamps visible.
    } finally {
      _refreshingVitals = false;
    }
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dashFuture = CaregiverApiService.instance.getElderDashboard(widget.elderProfileId);
      final hrFuture = CaregiverApiService.instance.getHeartRate24h(widget.elderProfileId);
      final thresholdFuture = CaregiverApiService.instance.getElderThresholds(widget.elderProfileId);
      final bpFuture = CaregiverApiService.instance.getBloodPressureHistory(widget.elderProfileId);
      final spo2Future = CaregiverApiService.instance.getSpo224h(widget.elderProfileId);
      final stepsFuture = CaregiverApiService.instance.getHourlySteps24h(widget.elderProfileId);
      final sleepFuture = CaregiverApiService.instance.getElderSleepSummary(widget.elderProfileId);

      final results = await Future.wait([
        dashFuture,
        hrFuture,
        thresholdFuture,
        bpFuture,
        spo2Future,
        stepsFuture,
        sleepFuture,
      ]);

      if (mounted) {
        setState(() {
          _dashboard = results[0] as ElderDashboard;
          _heartRate24h = results[1] as HeartRate24hData;
          _thresholdData = results[2] as ThresholdData;
          _bloodPressureHistory = results[3] as BloodPressureHistoryData;
          _spo224h = results[4] as Spo224hData;
          _hourlySteps24h = results[5] as HourlyStepsData;
          _sleepSummary = results[6] as SleepSummaryData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generatePin() async {
    setState(() => _isGeneratingPin = true);
    try {
      final pin = await CaregiverApiService.instance.generatePin(widget.elderProfileId);
      if (mounted) {
        setState(() {
          _generatedPin = pin;
          _pinExpiresAt = DateTime.now().add(const Duration(minutes: 10));
          _isGeneratingPin = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mã PIN ghép nối: $pin (Hiệu lực 10 phút)'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể sinh mã PIN: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  LatLng _parseGpsLocation(String? loc) {
    if (loc == null || loc.isEmpty) {
      return const LatLng(10.776889, 106.700806); // Mặc định TP. Hồ Chí Minh
    }
    try {
      final parts = loc.split(',');
      if (parts.length >= 2) {
        final lat = double.parse(parts[0].trim());
        final lng = double.parse(parts[1].trim());
        return LatLng(lat, lng);
      }
    } catch (_) {}
    return const LatLng(10.776889, 106.700806);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.elderName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
            ),
            const Text(
              'Bảng Điều Khiển Sinh Hiệu & Vị Trí',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Lịch sử sự cố của cụ',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncidentHistoryScreen(
                  initialElderProfileId: widget.elderProfileId,
                  initialElderName: widget.elderName,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Góc Sức Khỏe AI',
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8)),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HealthCornerScreen(elderId: widget.elderProfileId),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Làm mới dữ liệu',
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: Color(0xFFEF4444)),
                        const SizedBox(height: 14),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Thử Lại'),
                          onPressed: _loadDashboard,
                        ),
                      ],
                    ),
                  ),
                )
              : _buildDashboardContent(),
    );
  }

  Widget _buildDashboardContent() {
    final d = _dashboard!;
    final isOnline = d.deviceStatus == 'ONLINE';
    final gpsCoord = _parseGpsLocation(d.lastKnownGpsLocation);

    return SafeArea(
      top: false,
      bottom: true,
      child: RefreshIndicator(
        color: const Color(0xFF38BDF8),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: _loadDashboard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cảnh báo khẩn cấp nếu có sự cố đang mở
              if (d.activeEmergency != null) ...[
                _buildEmergencyAlertBanner(d.activeEmergency!),
                const SizedBox(height: 14),
              ],
              if (d.demoHeartRate != null || d.demoSpO2 != null) ...[
                _buildDemoAlertBanner(d),
                const SizedBox(height: 14),
              ],

              // 1. THẺ HỒ SƠ NGƯỜI CAO TUỔI & TRẠNG THÁI THIẾT BỊ
              _buildElderProfileCard(d, isOnline),
              const SizedBox(height: 14),

              // 1.1 GÓC SỨC KHỎE AI (PHẦN 4: NHẬN ĐỊNH SỨC KHỎE & BÁO CÁO TUẦN)
              _buildHealthCornerCard(),
              const SizedBox(height: 14),

              // 2. LƯỚI CHỈ SỐ SINH HIỆU THỜI GIAN THỰC (4 CARDS)
              _buildVitalsHeader(),
              const SizedBox(height: 10),
              _buildVitalsGrid(d),
              const SizedBox(height: 12),
              _buildCareAdviceCard(d),
              const SizedBox(height: 18),

              // 3. KHU VỰC PHÂN TÍCH BIỂU ĐỒ SINH HIỆU CHUYÊN SÂU (GÓI A: 4 BIỂU ĐỒ)
              _buildVitalsAnalyticsCard(),
              const SizedBox(height: 18),

              // 4. BẢN ĐỒ GPS ĐỊNH VỊ VỊ TRÍ HIỆN TẠI (FLUTTER_MAP)
              _buildGpsMapCard(d, gpsCoord),
              const SizedBox(height: 18),

              // 5. TỔNG KẾT GIẤC NGỦ & NHỊP SINH HỌC (GÓI B)
              _buildSleepSummaryCard(),
              const SizedBox(height: 18),

              // 6. THẺ NGƯỠNG AN TOÀN THÍCH NGHI & NHỊP SINH HỌC (ADAPTIVE AI & GÓI B)
              _buildAdaptiveThresholdCard(),
              const SizedBox(height: 18),

              // 7. THẺ GHÉP NỐI THIẾT BỊ & MÃ PIN (PIN GENERATION)
              _buildPairingPinCard(),
              const SizedBox(height: 16),

              // Dấu mốc đồng bộ lần cuối
              if (d.lastSyncedAt != null)
                Center(
                  child: Text(
                    'Đồng bộ dữ liệu lúc: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(d.lastSyncedAt!.toLocal())}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  // --- THẺ HỒ SƠ ---
  Widget _buildElderProfileCard(ElderDashboard d, bool isOnline) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                d.fullName.isNotEmpty ? d.fullName[0].toUpperCase() : 'C',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        d.fullName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isOnline ? const Color(0xFF064E3B) : const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isOnline ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isOnline ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOnline ? const Color(0xFF6EE7B7) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${d.age} tuổi',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    ),
                    const Text(' • ', style: TextStyle(color: Color(0xFF64748B))),
                    const Icon(Icons.watch_rounded, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 4),
                    Text(
                      d.lastSyncedAt == null ? 'Chưa ghép đồng hồ' : 'Đồng hồ CareAI',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- GÓC SỨC KHỎE AI (PHẦN 4) ---
  Widget _buildHealthCornerCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 22),
        ),
        title: const Text(
          'Góc Sức Khỏe AI',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
        ),
        subtitle: const Text(
          'Nhận định xu hướng & Báo cáo tổng kết tuần',
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HealthCornerScreen(elderId: widget.elderProfileId),
          ),
        ),
        ),
      ),
    );
  }

  // --- LƯỚI SINH HIỆU ---
  Widget _buildVitalsHeader() {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.monitor_heart_rounded, color: Color(0xFF38BDF8), size: 18),
            SizedBox(width: 8),
            Text(
              'Chỉ Số Sinh Hiệu Thời Gian Thực',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        Text(
          'Chuẩn y tế',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  Widget _buildVitalsGrid(ElderDashboard d) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildVitalCard(
                title: 'Nhịp tim',
                value: d.latestHeartRate != null ? '${d.latestHeartRate!.value.toInt()}' : '--',
                unit: 'bpm',
                icon: Icons.favorite_rounded,
                iconColor: const Color(0xFFEF4444),
                accentColor: const Color(0xFFEF4444),
                timestamp: d.latestHeartRate?.timestamp,
                statusText: d.latestHeartRate != null
                    ? (d.latestHeartRate!.value > 100
                        ? 'Nhịp nhanh'
                        : (d.latestHeartRate!.value < 50 ? 'Nhịp chậm' : 'Bình thường'))
                    : 'Chưa có mẫu',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildVitalCard(
                title: 'Oxy Máu (SpO2)',
                value: d.latestSpO2 != null ? d.latestSpO2!.value.toStringAsFixed(1) : '--',
                unit: '%',
                icon: Icons.air_rounded,
                iconColor: const Color(0xFF0EA5E9),
                accentColor: const Color(0xFF0EA5E9),
                timestamp: d.latestSpO2?.timestamp,
                statusText: d.latestSpO2 != null
                    ? (d.latestSpO2!.value < 95 ? 'Oxy thấp' : 'Tối ưu')
                    : 'Chưa có mẫu',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildVitalCard(
                title: 'Huyết Áp',
                value: d.latestBloodPressure != null ? '${d.latestBloodPressure!.value.toInt()}' : '--',
                unit: 'mmHg',
                icon: Icons.speed_rounded,
                iconColor: const Color(0xFFA855F7),
                accentColor: const Color(0xFFA855F7),
                timestamp: d.latestBloodPressure?.timestamp,
                statusText: d.latestBloodPressure == null ? 'Chưa có mẫu' : 'Đã cập nhật',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildVitalCard(
                title: 'Vận Động Hôm Nay',
                value: '${d.todaySteps}',
                unit: 'bước',
                icon: Icons.directions_walk_rounded,
                iconColor: const Color(0xFF10B981),
                accentColor: const Color(0xFF10B981),
                timestamp: null,
                statusText: 'Mục tiêu: ${d.stepGoal}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDemoAlertBanner(ElderDashboard dashboard) {
    final heartRate = dashboard.demoHeartRate;
    final spo2 = dashboard.demoSpO2;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF422006),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CẢNH BÁO TRÌNH DIỄN · DỮ LIỆU GIẢ LẬP',
              style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
          if (heartRate != null)
            Text('Nhịp tim tăng: ${heartRate.value.toStringAsFixed(0)} bpm · '
                '${DateFormat('HH:mm:ss').format(heartRate.timestamp.toLocal())}',
                style: const TextStyle(color: Colors.white)),
          if (spo2 != null)
            Text('SpO₂ giảm: ${spo2.value.toStringAsFixed(0)}% · '
                '${DateFormat('HH:mm:ss').format(spo2.timestamp.toLocal())}',
                style: const TextStyle(color: Colors.white)),
          const Text('Chỉ dùng để thử luồng đồng bộ. Không phải số đo lâm sàng từ thiết bị.',
              style: TextStyle(color: Color(0xFFFDE68A), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCareAdviceCard(ElderDashboard d) {
    final now = DateTime.now();
    final hr = d.latestHeartRate;
    final oxygen = d.latestSpO2;
    final messages = <String>[];
    if (hr == null && oxygen == null) {
      messages.add('Chưa có mẫu nhịp tim hoặc SpO₂. Kiểm tra kết nối đồng hồ, quyền truy cập sức khỏe và mạng.');
    } else {
      if (hr == null) messages.add('Chưa có mẫu nhịp tim. Kiểm tra quyền cảm biến nhịp tim trên đồng hồ.');
      if (oxygen == null) messages.add('Chưa có mẫu SpO₂. Kiểm tra quyền cảm biến SpO₂ và khả năng đo của đồng hồ.');
      if (hr != null) {
        if (now.difference(hr.timestamp).inHours >= 2) {
          messages.add('Mẫu nhịp tim đã cũ. Kiểm tra đồng hồ và thời điểm đồng bộ.');
        } else if (hr.value < 50 || hr.value > 100) {
          messages.add('Nhịp tim gần nhất nằm ngoài khoảng tham chiếu trên app. Hãy hỏi thăm cảm giác của người thân.');
        }
      }
      if (oxygen != null) {
        if (now.difference(oxygen.timestamp).inHours >= 2) {
          messages.add('Mẫu SpO₂ đã cũ. Kiểm tra đồng hồ và thời điểm đồng bộ.');
        } else if (oxygen.value < 95) {
          messages.add('SpO₂ gần nhất thấp: hỏi thăm triệu chứng, kiểm tra lại phép đo và liên hệ nhân viên y tế nếu mức thấp lặp lại.');
        }
      }
      if (messages.isEmpty) {
        messages.add('Chỉ số mới nhất đã được cập nhật. Tiếp tục theo dõi xu hướng và hỏi thăm người thân.');
      }
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Color(0xFF38BDF8), size: 18),
                SizedBox(width: 6),
                Text('Nhận định cho gia đình',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            InkWell(
              onTap: () => setState(() => _isAdviceExpanded = !_isAdviceExpanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isAdviceExpanded ? 'Thu gọn' : 'Xem (${messages.length})',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _isAdviceExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: const Color(0xFF94A3B8),
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_isAdviceExpanded) ...[
          const SizedBox(height: 8),
          ...messages.map((message) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text('• $message', style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
          )),
          const SizedBox(height: 2),
          const Text('Chỉ hỗ trợ theo dõi, không thay thế đánh giá y tế.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required Color accentColor,
    required DateTime? timestamp,
    required String statusText,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accentColor),
                ),
              ),
              if (timestamp != null)
                Text(
                  DateFormat('HH:mm').format(timestamp.toLocal()),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- KHU VỰC PHÂN TÍCH BIỂU ĐỒ SINH HIỆU CHUYÊN SÂU (GÓI A: 4 BIỂU ĐỒ) ---
  Widget _buildVitalsAnalyticsCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Bộ chuyển đổi 4 Tab biểu đồ
          _buildChartTabBar(),
          const SizedBox(height: 16),

          // 2. Nội dung biểu đồ tương ứng
          if (_selectedChartTab == 0)
            _buildHeartRateChartContent()
          else if (_selectedChartTab == 1)
            _buildBloodPressureChartContent()
          else if (_selectedChartTab == 2)
            _buildSpo2ChartContent()
          else
            _buildHourlyStepsChartContent(),
        ],
      ),
    );
  }

  Widget _buildChartTabBar() {
    final tabs = [
      (index: 0, label: 'Nhịp tim', icon: Icons.favorite_rounded, color: const Color(0xFFEF4444)),
      (index: 1, label: 'Huyết áp', icon: Icons.speed_rounded, color: const Color(0xFFA855F7)),
      (index: 2, label: 'SpO2', icon: Icons.air_rounded, color: const Color(0xFF0EA5E9)),
      (index: 3, label: 'Vận động', icon: Icons.directions_walk_rounded, color: const Color(0xFF10B981)),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: tabs.map((t) {
          final isSelected = _selectedChartTab == t.index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _selectedChartTab = t.index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? t.color.withValues(alpha: 0.2) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? t.color : const Color(0xFF334155),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t.icon,
                      size: 15,
                      color: isSelected ? t.color : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeartRateChartContent() {
    final hrData = _heartRate24h;
    final points = hrData?.points ?? [];

    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: Text('Chưa có mẫu nhịp tim trong 24 giờ qua',
            style: TextStyle(color: Color(0xFF94A3B8)))),
      );
    }

    List<FlSpot> spots = [];
    if (points.isNotEmpty) {
      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(hours: 24));
      for (int i = 0; i < points.length; i++) {
        final diffHours = points[i].timestamp.difference(windowStart).inMinutes / 60.0;
        final clampedX = diffHours.clamp(0.0, 24.0);
        spots.add(FlSpot(clampedX, points[i].value));
      }
      spots.sort((a, b) => a.x.compareTo(b.x));
    }

    final double minVal = hrData?.minHeartRate ?? 60.0;
    final double maxVal = hrData?.maxHeartRate ?? 100.0;
    final double avgVal = hrData?.avgHeartRate ?? 74.0;

    // Tính cận trên và cận dưới linh hoạt theo dữ liệu thực tế
    final double computedMaxY = (((maxVal > 120 ? maxVal : 120) + 15) / 10).ceil() * 10.0;
    final double computedMinY = (((minVal < 50 ? minVal : 50) - 15) / 10).floor() * 10.0;
    final double chartMaxY = computedMaxY.clamp(130.0, 320.0);
    final double chartMinY = computedMinY.clamp(0.0, 60.0);
    final double yInterval = ((chartMaxY - chartMinY) / 4).clamp(15.0, 40.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart_rounded, color: Color(0xFFEF4444), size: 18),
                SizedBox(width: 8),
                Text(
                  'Biến Thiên Nhịp Tim (24h)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Text('24 giờ qua', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3 Thẻ thống kê Min / TB / Max
        Row(
          children: [
            _buildStatPill('Thấp nhất', '${minVal.toInt()} bpm', const Color(0xFF10B981)),
            const SizedBox(width: 8),
            _buildStatPill('Trung bình', '${avgVal.toStringAsFixed(1)} bpm', const Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            _buildStatPill('Cao nhất', '${maxVal.toInt()} bpm', const Color(0xFFF97316)),
          ],
        ),
        const SizedBox(height: 18),

        // Khung vẽ biểu đồ
        SizedBox(
          height: 190,
          child: ClipRect(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: Color(0xFF334155),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 6,
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${value.toInt()}h',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 24,
                minY: chartMinY,
                maxY: chartMaxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: spots.length > 2,
                    curveSmoothness: 0.25,
                    color: const Color(0xFFEF4444),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: spots.length <= 5),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFEF4444).withValues(alpha: 0.3),
                          const Color(0xFFEF4444).withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 12, color: Color(0xFF10B981)),
            SizedBox(width: 4),
            Text(
              'Dải an toàn lâm sàng: 60 - 100 bpm (Nghỉ ngơi)',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBloodPressureChartContent() {
    final bp = _bloodPressureHistory;
    final points = bp?.points ?? [];

    List<FlSpot> sysSpots = [];
    List<FlSpot> diaSpots = [];

    if (points.isNotEmpty) {
      for (int i = 0; i < points.length; i++) {
        sysSpots.add(FlSpot(i.toDouble(), points[i].systolic));
        diaSpots.add(FlSpot(i.toDouble(), points[i].diastolic));
      }
    } else {
      sysSpots = const [
        FlSpot(0, 118),
        FlSpot(1, 122),
        FlSpot(2, 125),
        FlSpot(3, 120),
        FlSpot(4, 128),
        FlSpot(5, 122),
        FlSpot(6, 120),
      ];
      diaSpots = const [
        FlSpot(0, 76),
        FlSpot(1, 78),
        FlSpot(2, 80),
        FlSpot(3, 78),
        FlSpot(4, 82),
        FlSpot(5, 80),
        FlSpot(6, 80),
      ];
    }

    final double latestSys = bp?.latestSystolic ?? 120.0;
    final double latestDia = bp?.latestDiastolic ?? 80.0;
    final String classification = bp?.classification ?? 'Bình thường';
    final String statusColor = bp?.statusColor ?? 'GREEN';

    Color badgeColor = const Color(0xFF10B981);
    if (statusColor == 'RED') {
      badgeColor = const Color(0xFFEF4444);
    } else if (statusColor == 'YELLOW') {
      badgeColor = const Color(0xFFF59E0B);
    }

    final double maxX = (points.isNotEmpty ? points.length - 1 : 6).toDouble().clamp(1.0, 30.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.speed_rounded, color: Color(0xFFA855F7), size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Xu Hướng Huyết Áp (14 Ngày)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                classification,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: badgeColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3 Thẻ thống kê
        Row(
          children: [
            _buildStatPill('Mới nhất', '${latestSys.toInt()}/${latestDia.toInt()} mmHg', const Color(0xFFA855F7)),
            const SizedBox(width: 8),
            _buildStatPill('Tâm thu Max', '${points.isNotEmpty ? points.map((p) => p.systolic).reduce((a, b) => a > b ? a : b).toInt() : 128} mmHg', const Color(0xFFEF4444)),
            const SizedBox(width: 8),
            _buildStatPill('Tâm trương Max', '${points.isNotEmpty ? points.map((p) => p.diastolic).reduce((a, b) => a > b ? a : b).toInt() : 82} mmHg', const Color(0xFF06B6D4)),
          ],
        ),
        const SizedBox(height: 18),

        // Khung vẽ biểu đồ 2 đường
        SizedBox(
          height: 190,
          child: ClipRect(
            child: LineChart(
              LineChartData(
                extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 120,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                  HorizontalLine(
                    y: 80,
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ],
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (value) => const FlLine(
                  color: Color(0xFF334155),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: points.length > 7 ? 2 : 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (points.isNotEmpty && idx >= 0 && idx < points.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('dd/MM').format(points[idx].timestamp.toLocal()),
                            style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                          ),
                        );
                      } else if (points.isEmpty && idx >= 0 && idx <= 6) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('N${idx + 1}', style: const TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 20,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: maxX,
              minY: 50,
              maxY: 170,
              lineBarsData: [
                // Đường Tâm thu (Systolic - Đỏ)
                LineChartBarData(
                  spots: sysSpots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: const Color(0xFFEF4444),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 3,
                      color: const Color(0xFFEF4444),
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
                // Đường Tâm trương (Diastolic - Xanh ngọc)
                LineChartBarData(
                  spots: diaSpots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: const Color(0xFF06B6D4),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                      radius: 3,
                      color: const Color(0xFF06B6D4),
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),

        // Chú thích 2 đường & ngưỡng
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Tâm thu', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
            const SizedBox(width: 14),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF06B6D4), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Tâm trương', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
            const SizedBox(width: 14),
            const Icon(Icons.horizontal_rule_rounded, size: 14, color: Color(0xFFF59E0B)),
            const Text('Chuẩn 120/80', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
          ],
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Phân loại WHO: Tối ưu < 120/80 | Tiền THA: 120-139 / 80-89 | THA: >= 140/90 mmHg',
            style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildSpo2ChartContent() {
    final spo2 = _spo224h;
    final points = spo2?.points ?? [];

    if (points.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(child: Text('Chưa có mẫu SpO₂ trong 24 giờ qua',
            style: TextStyle(color: Color(0xFF94A3B8)))),
      );
    }

    List<FlSpot> spots = [];
    if (points.isNotEmpty) {
      final windowStart = DateTime.now().subtract(const Duration(hours: 24));
      for (int i = 0; i < points.length; i++) {
        final hoursDiff = points[i].timestamp.toLocal().difference(windowStart).inMinutes / 60.0;
        spots.add(FlSpot(hoursDiff.clamp(0.0, 24.0), points[i].value));
      }
    }

    final double minVal = spo2?.minSpo2 ?? 96.0;
    final double avgVal = spo2?.avgSpo2 ?? 97.8;
    final int dipsCount = spo2?.dipsBelow95Count ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Row(
                children: [
                  Icon(Icons.air_rounded, color: Color(0xFF0EA5E9), size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Nồng Độ Oxy Máu (SpO2 24h)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: dipsCount > 0 ? const Color(0xFF451A03) : const Color(0xFF064E3B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: dipsCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                ),
              ),
              child: Text(
                dipsCount > 0 ? 'Có $dipsCount cơn tụt oxy' : 'Oxy bão hòa tốt',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: dipsCount > 0 ? const Color(0xFFFDE68A) : const Color(0xFF6EE7B7),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3 Thẻ thống kê
        Row(
          children: [
            _buildStatPill('Thấp nhất', '${minVal.toStringAsFixed(1)}%', minVal < 95 ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
            const SizedBox(width: 8),
            _buildStatPill('Trung bình', '${avgVal.toStringAsFixed(1)}%', const Color(0xFF0EA5E9)),
            const SizedBox(width: 8),
            _buildStatPill('Cơn tụt <95%', '$dipsCount lần', dipsCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
          ],
        ),
        const SizedBox(height: 18),

        // Khung vẽ biểu đồ SpO2
        SizedBox(
          height: 190,
          child: ClipRect(
            child: LineChart(
              LineChartData(
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 95,
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.6),
                    strokeWidth: 1.2,
                    dashArray: [5, 5],
                  ),
                  HorizontalLine(
                    y: 90,
                    color: const Color(0xFFEF4444).withValues(alpha: 0.7),
                    strokeWidth: 1.2,
                    dashArray: [5, 5],
                  ),
                ],
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 5,
                getDrawingHorizontalLine: (value) => const FlLine(
                  color: Color(0xFF334155),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 6,
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${value.toInt()}h',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 5,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}%',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: 24,
              minY: (((minVal - 5) / 5).floor() * 5).clamp(0, 85).toDouble(),
              maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: const Color(0xFF0EA5E9),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: spots.length == 1),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                        const Color(0xFF0EA5E9).withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),

        // Chú thích các vạch cảnh báo
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.horizontal_rule_rounded, size: 14, color: Color(0xFFF59E0B)),
            Text('Vạch vàng < 95% (Cảnh báo)', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
            SizedBox(width: 14),
            Icon(Icons.horizontal_rule_rounded, size: 14, color: Color(0xFFEF4444)),
            Text('Vạch đỏ < 90% (Cấp cứu)', style: TextStyle(fontSize: 10, color: Color(0xFFEF4444))),
          ],
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Ngưỡng an toàn: >= 95%. Cơn tụt oxy lặp lại về đêm là dấu hiệu nguy hiểm (ngưng thở khi ngủ)',
            style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildHourlyStepsChartContent() {
    final stepsData = _hourlySteps24h;
    final list = stepsData?.hourlySteps ?? [];
    final int totalSteps = stepsData?.totalStepsToday ?? 0;
    final int peakHour = stepsData?.peakHour ?? 7;
    final int peakSteps = stepsData?.peakSteps ?? 0;

    List<BarChartGroupData> barGroups = [];
    if (list.isNotEmpty) {
      for (final item in list) {
        final isPeak = item.hour == peakHour && item.steps > 0;
        barGroups.add(
          BarChartGroupData(
            x: item.hour,
            barRods: [
              BarChartRodData(
                toY: item.steps.toDouble(),
                color: isPeak ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                width: 7,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          ),
        );
      }
    } else {
      final sampleHours = {6: 450, 7: 620, 8: 380, 11: 210, 16: 520, 17: 410};
      for (int h = 0; h < 24; h++) {
        final val = (sampleHours[h] ?? 0).toDouble();
        barGroups.add(
          BarChartGroupData(
            x: h,
            barRods: [
              BarChartRodData(
                toY: val,
                color: h == 7 ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                width: 7,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          ),
        );
      }
    }

    final double maxY = ((peakSteps > 0 ? peakSteps : 620) * 1.25).clamp(300.0, 10000.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.directions_walk_rounded, color: Color(0xFF10B981), size: 18),
                SizedBox(width: 8),
                Text(
                  'Phân Bố Vận Động (24 Giờ)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Text('Theo từng giờ', style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3 Thẻ thống kê
        Row(
          children: [
            _buildStatPill('Tổng bước', '$totalSteps', const Color(0xFF10B981)),
            const SizedBox(width: 8),
            _buildStatPill('Cao điểm', '${peakHour}h ($peakSteps)', const Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            _buildStatPill('Mục tiêu ngày', '${((totalSteps / 6000) * 100).clamp(0, 100).toInt()}%', const Color(0xFFA855F7)),
          ],
        ),
        const SizedBox(height: 18),

        // Khung vẽ BarChart
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (value) => const FlLine(
                  color: Color(0xFF334155),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 4,
                    getTitlesWidget: (value, meta) {
                      final v = value.toInt();
                      if (v % 4 != 0 && v != 23) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${v}h',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY,
              barGroups: barGroups,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Chú thích
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Giờ cao điểm', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
            const SizedBox(width: 14),
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF38BDF8), shape: BoxShape.circle)),
            const SizedBox(width: 4),
            const Text('Vận động thường', style: TextStyle(fontSize: 10, color: Color(0xFFCBD5E1))),
          ],
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Nhịp sinh học: Phát hiện thói quen thức giấc đêm hoặc suy giảm vận động đột ngột',
            style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatPill(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // --- BẢN ĐỒ GPS & LIÊN KẾT GOOGLE MAPS (TUÂN THỦ: KHÔNG DÙNG BẢN ĐỒ TRUNG QUỐC) ---
  Widget _buildGpsMapCard(ElderDashboard d, LatLng coord) {
    final googleMapsLink =
        'https://www.google.com/maps/search/?api=1&query=${coord.latitude},${coord.longitude}';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.location_on_rounded, color: Color(0xFF38BDF8), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Vị Trí Định Vị Trực Tiếp (GPS)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.gps_fixed_rounded, size: 10, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text('Trực tuyến', style: TextStyle(fontSize: 10, color: Color(0xFF6EE7B7), fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Khung Bản đồ (OpenStreetMap Chuẩn Quốc Tế, Không Sử Dụng Bản Đồ Trung Quốc)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: coord,
                      initialZoom: 15.5,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'vn.careai.companion',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: coord,
                            width: 50,
                            height: 50,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Sóng radar lan tỏa
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                                  ),
                                ),
                                // Vòng tròn pin chính
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0284C7),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.person, size: 12, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Thanh nổi thông tin tọa độ & sao chép link Google Maps
                  Positioned(
                    bottom: 8,
                    left: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pin_drop, color: Color(0xFF38BDF8), size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tọa độ: ${coord.latitude.toStringAsFixed(6)}, ${coord.longitude.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFE2E8F0), fontWeight: FontWeight.w500),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: googleMapsLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã sao chép link Google Maps vào bộ nhớ tạm!'),
                                  backgroundColor: Color(0xFF0284C7),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.copy, size: 12, color: Color(0xFF94A3B8)),
                                  SizedBox(width: 2),
                                  Text('Sao chép', style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // HÀNG NÚT TÁC VỤ GOOGLE MAPS
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text(
                    'Mở Trên Google Maps',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => LocationService.instance.openGoogleMaps(
                    coord.latitude,
                    coord.longitude,
                    label: 'Vị trí Cụ ${d.fullName}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF38BDF8), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text(
                    'Chỉ Đường',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => LocationService.instance.openGoogleMapsDirections(
                    coord.latitude,
                    coord.longitude,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- THẺ TỔNG KẾT GIẤC NGỦ & NHỊP SINH HỌC (GÓI B) ---
  Widget _buildSleepSummaryCard() {
    final s = _sleepSummary;
    final hasData = s != null && s.totalSleepMinutes > 0;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.bedtime_rounded, color: Color(0xFF818CF8), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theo Dõi Giấc Ngủ Đêm Qua',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Khung giờ ngủ: ${_thresholdData?.sleepWindowStart ?? '22:00'} - ${_thresholdData?.sleepWindowEnd ?? '06:00'}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF6366F1)),
                ),
                child: Text(
                  s?.sleepQuality ?? 'Chưa có',
                  style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (!hasData)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFF94A3B8), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chưa ghi nhận phiên ngủ đêm qua từ thiết bị đeo hoặc cụ đang trong khung giờ thức ban ngày.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TỔNG THỜI GIAN NGỦ', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          s.formattedDuration,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFA5B4FC)),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 40, color: const Color(0xFF334155)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GIẤC NGỦ SÂU (DEEP)', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          s.formattedDeepSleep,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Thanh phân bổ các giai đoạn ngủ
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (s.deepSleepMinutes > 0)
                      Expanded(
                        flex: s.deepSleepMinutes,
                        child: Container(color: const Color(0xFF4F46E5)),
                      ),
                    if (s.lightSleepMinutes > 0)
                      Expanded(
                        flex: s.lightSleepMinutes,
                        child: Container(color: const Color(0xFF38BDF8)),
                      ),
                    if (s.wakeCount > 0)
                      Expanded(
                        flex: (s.wakeCount * 10).clamp(5, 50),
                        child: Container(color: const Color(0xFFF59E0B)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Chú thích
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF4F46E5), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Sâu: ${s.formattedDeepSleep}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF38BDF8), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Nông: ${s.formattedLightSleep}', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Thức: ${s.wakeCount} lần', style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // --- THẺ NGƯỠNG AN TOÀN THÍCH NGHI & NHỊP SINH HỌC (ADAPTIVE AI & GÓI B) ---
  Widget _buildAdaptiveThresholdCard() {
    final dayMinBpm = _thresholdData?.restingHeartRateMin ?? 50.0;
    final dayMaxBpm = _thresholdData?.restingHeartRateMax ?? 120.0;
    final nightMinBpm = _thresholdData?.nightHeartRateMin ?? 40.0;
    final nightMaxBpm = _thresholdData?.nightHeartRateMax ?? 90.0;
    final sleepStart = _thresholdData?.sleepWindowStart ?? '22:00';
    final sleepEnd = _thresholdData?.sleepWindowEnd ?? '06:00';
    final hasUpdated = _thresholdData?.updatedAt != null;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune_rounded, color: Color(0xFF2DD4BF), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ngưỡng Nhịp Tim Sinh Học (AI)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Tự động phân tách Ngày vs Đêm chống báo động giả',
                      style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF0D9488)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: Color(0xFF2DD4BF), size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Circadian',
                      style: TextStyle(color: Color(0xFF2DD4BF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // HÀNG 1: BAN NGÀY (THỨC)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFBBF24), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'Ban Ngày ($sleepEnd - $sleepStart)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFBBF24)),
                    ),
                    const Spacer(),
                    const Text('Chuẩn hoạt động', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('NGƯỠNG DƯỚI', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${dayMinBpm.toStringAsFixed(0)} bpm', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                      ],
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFF334155)),
                    Column(
                      children: [
                        const Text('NGƯỠNG TRÊN', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${dayMaxBpm.toStringAsFixed(0)} bpm', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFF87171))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // HÀNG 2: BAN ĐÊM (NGỦ)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.nights_stay_rounded, color: Color(0xFF818CF8), size: 15),
                    const SizedBox(width: 6),
                    Text(
                      'Ban Đêm ($sleepStart - $sleepEnd)',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF818CF8)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Chống báo động giả', style: TextStyle(fontSize: 10, color: Color(0xFFA5B4FC), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('NGƯỠNG DƯỚI ĐÊM', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${nightMinBpm.toStringAsFixed(0)} bpm', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF818CF8))),
                      ],
                    ),
                    Container(width: 1, height: 28, color: const Color(0xFF334155)),
                    Column(
                      children: [
                        const Text('NGƯỠNG TRÊN ĐÊM', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('${nightMaxBpm.toStringAsFixed(0)} bpm', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFB7185))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (hasUpdated) ...[
            const SizedBox(height: 8),
            Text(
              'Tối ưu lần cuối: ${DateFormat('dd/MM/yyyy HH:mm').format(_thresholdData!.updatedAt!.toLocal())}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isAnalyzingThresholds
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.insights_rounded, size: 18),
              label: Text(
                _isAnalyzingThresholds ? 'Đang phân tích dữ liệu 14 ngày...' : 'PHÂN TÍCH AI & ĐỀ XUẤT NGƯỠNG MỚI',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: _isAnalyzingThresholds ? null : () => _analyzeAndShowTuningSheet(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _analyzeAndShowTuningSheet() async {
    setState(() => _isAnalyzingThresholds = true);
    try {
      final rec = await CaregiverApiService.instance.getThresholdRecommendation(widget.elderProfileId);
      if (!mounted) return;
      setState(() => _isAnalyzingThresholds = false);

      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1E293B),
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _buildTuningModal(ctx, rec),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzingThresholds = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi phân tích ngưỡng: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildTuningModal(BuildContext ctx, ThresholdRecommendation rec) {
    return SafeArea(
      top: false,
      bottom: true,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF475569),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF2DD4BF), size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đề Xuất Ngưỡng Thích Nghi (AI)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    Text(
                      'Phân tích bách phân vị P5/P95 chuỗi nhịp tim 14 ngày',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Khối so sánh ngưỡng Hiện tại vs Đề xuất mới
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Dải ngưỡng hiện tại:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    Text(
                      '${rec.currentMinBpm.toStringAsFixed(0)} - ${rec.currentMaxBpm.toStringAsFixed(0)} bpm',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF334155), height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Bách phân vị thực tế:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                    Text(
                      'P5: ${rec.calculatedP5.toStringAsFixed(1)} | P95: ${rec.calculatedP95.toStringAsFixed(1)} bpm',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF334155), height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Đề xuất mới (Clamped ±3):', style: TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.bold, fontSize: 13)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2DD4BF)),
                      ),
                      child: Text(
                        '${rec.recommendedMinBpm.toStringAsFixed(0)} - ${rec.recommendedMaxBpm.toStringAsFixed(0)} bpm',
                        style: const TextStyle(color: Color(0xFF2DD4BF), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Giải trình lâm sàng (Clinical Rationale)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A).withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rec.clinicalRationale,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Nút áp dụng ngưỡng mới
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: const Text(
                'ÁP DỤNG DẢI NGƯỠNG ĐỀ XUẤT NÀY',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final updated = await CaregiverApiService.instance.updateElderThresholds(
                    widget.elderProfileId,
                    rec.recommendedMinBpm,
                    rec.recommendedMaxBpm,
                    nightMinBpm: _thresholdData?.nightHeartRateMin ?? 40.0,
                    nightMaxBpm: _thresholdData?.nightHeartRateMax ?? 90.0,
                    sleepStart: _thresholdData?.sleepWindowStart ?? '22:00',
                    sleepEnd: _thresholdData?.sleepWindowEnd ?? '06:00',
                  );
                  if (mounted) {
                    setState(() {
                      _thresholdData = updated;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã áp dụng ngưỡng thích nghi mới: ${updated.restingHeartRateMin.toStringAsFixed(0)} - ${updated.restingHeartRateMax.toStringAsFixed(0)} bpm!',
                        ),
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Không thể cập nhật ngưỡng: $e'),
                        backgroundColor: const Color(0xFFEF4444),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

  // --- THẺ MÃ PIN GHÉP NỐI ---
  Widget _buildPairingPinCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.pin_rounded, color: Color(0xFF38BDF8), size: 18),
              SizedBox(width: 8),
              Text(
                'Mã PIN Ghép Nối Thiết Bị',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Nhập mã PIN 6 số này vào điện thoại hoặc Galaxy Watch của Cụ để kích hoạt liên kết:',
            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
          if (_generatedPin != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    _generatedPin!,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hết hạn lúc: ${DateFormat('HH:mm:ss').format(_pinExpiresAt ?? DateTime.now())}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF0284C7)),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isGeneratingPin
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)))
                : const Icon(Icons.autorenew_rounded, size: 18),
            label: Text(_generatedPin == null ? 'SINH MÃ PIN MỚI (10 PHÚT)' : 'ĐỔI MÃ PIN MỚI'),
            onPressed: _isGeneratingPin ? null : _generatePin,
          ),
        ],
      ),
    );
  }

  // --- BANNER CẢNH BÁO KHẨN CẤP ---
  Widget _buildEmergencyAlertBanner(Incident inc) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF450A0A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEF4444), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  inc.emergencyType == 'FALL_DETECTED' ? 'PHÁT HIỆN TÉ NGÃ KHẨN CẤP!' : 'BÁO ĐỘNG SOS TỪ THIẾT BỊ!',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFFCA5A5)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: inc.isOpen ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  inc.isOpen ? 'CHƯA TIẾP NHẬN' : 'ĐÃ TIẾP NHẬN',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Thời gian: ${DateFormat('HH:mm:ss dd/MM').format(inc.triggeredAt.toLocal())}',
            style: const TextStyle(fontSize: 12, color: Color(0xFFFECACA)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('MỞ CHI TIẾT CỨU HỘ & XỬ LÝ', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: inc)),
                );
                if (changed == true) _loadDashboard();
              },
            ),
          ),
        ],
      ),
    );
  }
}
