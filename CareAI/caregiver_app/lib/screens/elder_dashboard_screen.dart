import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'incident_detail_screen.dart';

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

class _ElderDashboardScreenState extends State<ElderDashboardScreen> {
  ElderDashboard? _dashboard;
  bool _isLoading = true;
  String? _errorMessage;

  // Trạng thái mã PIN
  String? _generatedPin;
  DateTime? _pinExpiresAt;
  bool _isGeneratingPin = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final data = await CaregiverApiService.instance.getElderDashboard(widget.elderProfileId);
      if (mounted) {
        setState(() {
          _dashboard = data;
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
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGeneratingPin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể sinh mã PIN: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.elderName),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 12),
                      Text(_errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadDashboard, child: const Text('Thử Lại')),
                    ],
                  ),
                )
              : _buildDashboardContent(),
    );
  }

  Widget _buildDashboardContent() {
    final d = _dashboard!;
    final isOnline = d.deviceStatus == 'ONLINE';

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cảnh báo khẩn cấp nếu có sự cố
            if (d.activeEmergency != null) ...[
              _buildEmergencyAlertBanner(d.activeEmergency!),
              const SizedBox(height: 16),
            ],

            // Thẻ Trạng thái Cụ & Thiết bị
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: const Color(0xFFE0F2FE),
                      child: Text(
                        d.fullName.isNotEmpty ? d.fullName[0].toUpperCase() : 'C',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.fullName,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 2),
                          Text('${d.age} tuổi', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOnline ? Colors.green : Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Thiết bị đang kết nối (Online)' : 'Thiết bị ngoại tuyến (Offline)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isOnline ? Colors.green[700] : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Mục Sinh mã PIN ghép nối
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.pin, color: Color(0xFF0284C7), size: 20),
                        SizedBox(width: 8),
                        Text('Mã PIN Ghép Nối Thiết Bị', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Dùng mã PIN 6 số này để nhập vào Companion App hoặc Galaxy Watch của Cụ để liên kết tài khoản:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    if (_generatedPin != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(12),
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
                                color: Color(0xFF0284C7),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hết hạn lúc: ${DateFormat('HH:mm:ss').format(_pinExpiresAt ?? DateTime.now())}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF0369A1)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0284C7),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                      ),
                      icon: _isGeneratingPin
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.autorenew, size: 18),
                      label: Text(_generatedPin == null ? 'SINH MÃ PIN MỚI (10 PHÚT)' : 'ĐỔI MÃ PIN MỚI'),
                      onPressed: _isGeneratingPin ? null : _generatePin,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Lưới Chỉ số Sinh hiệu
            const Text(
              'Chỉ Số Sinh Hiệu Thời Gian Thực',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildVitalCard(
                    title: 'Nhịp Tim (PPG)',
                    value: d.latestHeartRate != null ? '${d.latestHeartRate!.value.toInt()}' : '--',
                    unit: 'bpm',
                    icon: Icons.favorite,
                    iconColor: const Color(0xFFEF4444),
                    timestamp: d.latestHeartRate?.timestamp,
                    statusColor: d.latestHeartRate?.statusColor ?? 'GREY',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildVitalCard(
                    title: 'Oxy Máu (SpO2)',
                    value: d.latestSpO2 != null ? '${d.latestSpO2!.value.toInt()}' : '--',
                    unit: '%',
                    icon: Icons.water_drop,
                    iconColor: const Color(0xFF0EA5E9),
                    timestamp: d.latestSpO2?.timestamp,
                    statusColor: d.latestSpO2?.statusColor ?? 'GREY',
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
                    icon: Icons.speed,
                    iconColor: const Color(0xFF8B5CF6),
                    timestamp: d.latestBloodPressure?.timestamp,
                    statusColor: 'GREEN',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildVitalCard(
                    title: 'Vận Động Hôm Nay',
                    value: '${d.todaySteps}',
                    unit: '/ ${d.stepGoal} bước',
                    icon: Icons.directions_walk,
                    iconColor: const Color(0xFF10B981),
                    timestamp: null,
                    statusColor: 'GREEN',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (d.lastSyncedAt != null)
              Center(
                child: Text(
                  'Đồng bộ lần cuối: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(d.lastSyncedAt!.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyAlertBanner(Incident inc) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEF4444), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.2),
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
              const Icon(Icons.warning, color: Color(0xFFDC2626), size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  inc.emergencyType == 'FALL_DETECTED' ? 'PHÁT HIỆN TÉ NGÃ KHẨN CẤP!' : 'BÁO ĐỘNG SOS TỪ THIẾT BỊ!',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: inc.isOpen ? const Color(0xFFDC2626) : Colors.orange[800],
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
            style: const TextStyle(fontSize: 12, color: Color(0xFF7F1D1D)),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
              label: const Text('MỞ CHI TIẾT CỨU HỘ & XỬ LÝ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  Widget _buildVitalCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color iconColor,
    required DateTime? timestamp,
    required String statusColor,
  }) {
    Color cardColor = Colors.white;
    Color borderC = Colors.grey[200]!;
    if (statusColor == 'YELLOW') {
      borderC = Colors.amber[400]!;
    } else if (statusColor == 'RED') {
      borderC = Colors.red[400]!;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderC),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              Icon(icon, color: iconColor, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ],
          ),
          const SizedBox(height: 4),
          if (timestamp != null)
            Text(
              DateFormat('HH:mm').format(timestamp.toLocal()),
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
        ],
      ),
    );
  }
}
