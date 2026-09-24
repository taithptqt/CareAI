import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';

class IncidentDetailScreen extends StatefulWidget {
  final Incident incident;

  const IncidentDetailScreen({super.key, required this.incident});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  late Incident _incident;
  bool _isLoading = false;
  final _resolveNotesController = TextEditingController(text: 'Đã kiểm tra cụ an toàn, sức khỏe ổn định.');

  @override
  void initState() {
    super.initState();
    _incident = widget.incident;
  }

  Future<void> _acknowledge() async {
    setState(() => _isLoading = true);
    try {
      await CaregiverApiService.instance.acknowledgeIncident(_incident.id, 'Người thân đang đến hỗ trợ');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã tiếp nhận sự cố thành công! Cả gia đình đã được thông báo.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showResolveDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoàn Tất & Đóng Sự Cố'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ghi chú kết quả xử lý cứu nạn (lưu trữ kiểm toán y tế):',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _resolveNotesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nhập ghi chú xử lý...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
            onPressed: () async {
              Navigator.pop(ctx);
              await _resolve();
            },
            child: const Text('Xác Nhận Đóng', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve() async {
    setState(() => _isLoading = true);
    try {
      await CaregiverApiService.instance.resolveIncident(_incident.id, _resolveNotesController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Sự cố đã được đóng an toàn. Cụ đã sẵn sàng cho chu kỳ giám sát tiếp theo.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFall = _incident.emergencyType == 'FALL_DETECTED';
    final isOpen = _incident.isOpen;
    final isAck = _incident.isAcknowledged;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Chi Tiết Cứu Hộ Khẩn Cấp'),
        backgroundColor: isOpen ? const Color(0xFFDC2626) : const Color(0xFFD97706),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thẻ Tiêu đề khẩn cấp
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isOpen ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isOpen ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    isFall ? Icons.personal_injury : Icons.warning_amber_rounded,
                    size: 48,
                    color: isOpen ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isFall ? 'CẢNH BÁO TÉ NGÃ KHẨN CẤP' : 'CẢNH BÁO SOS TỪ CỤ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isOpen ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Người gặp nạn: ${_incident.elderName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOpen ? Colors.red[700] : Colors.amber[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isOpen ? 'TRẠNG THÁI: CHƯA TIẾP NHẬN' : 'TRẠNG THÁI: ĐÃ TIẾP NHẬN',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Thông tin chi tiết
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildInfoRow('Thời điểm kích hoạt:', DateFormat('HH:mm:ss - dd/MM/yyyy').format(_incident.triggeredAt.toLocal())),
                    const Divider(height: 20),
                    _buildInfoRow('Thiết bị phát hiện:', _incident.triggeredByDeviceId),
                    const Divider(height: 20),
                    _buildInfoRow('Mức độ nghiêm trọng:', _incident.severity),
                    if (_incident.acknowledgedAt != null) ...[
                      const Divider(height: 20),
                      _buildInfoRow('Tiếp nhận lúc:', DateFormat('HH:mm:ss - dd/MM/yyyy').format(_incident.acknowledgedAt!.toLocal())),
                    ],
                    if (_incident.resolvedAt != null) ...[
                      const Divider(height: 20),
                      _buildInfoRow('Đóng lúc:', DateFormat('HH:mm:ss - dd/MM/yyyy').format(_incident.resolvedAt!.toLocal())),
                      const Divider(height: 20),
                      _buildInfoRow('Ghi chú xử lý:', _incident.resolutionNotes ?? 'Không có'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Dòng thời gian Timeline cứu trợ (UC-14)
            const Text(
              'Dòng Thời Gian Cứu Nạn (Audit Timeline)',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 8),

            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _incident.timeline.isEmpty
                    ? const Text('Chưa có sự kiện timeline bổ sung', style: TextStyle(fontSize: 13, color: Colors.grey))
                    : Column(
                        children: _incident.timeline.map((t) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.circle, size: 10, color: Color(0xFF0284C7)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                      Text(
                                        DateFormat('HH:mm:ss').format(t.recordedAt.toLocal()),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Hàng Nút Hành Động
            if (isOpen) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('TIẾP NHẬN CỨU HỘ NGAY (ACK)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: _isLoading ? null : _acknowledge,
              ),
              const SizedBox(height: 12),
            ],

            if (isAck) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.task_alt, color: Colors.white),
                label: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('HOÀN TẤT & ĐÓNG SỰ CỐ (RESOLVE)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                onPressed: _isLoading ? null : _showResolveDialog,
              ),
              const SizedBox(height: 12),
            ],

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.phone_in_talk, color: Color(0xFFDC2626)),
              label: const Text('GỌI CẤP CỨU 115', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đang mô phỏng kết nối cuộc gọi khẩn cấp 115...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}
