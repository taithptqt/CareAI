import 'package:flutter/material.dart';
import '../services/caregiver_api_service.dart';

class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({super.key});

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  final _urlController = TextEditingController();
  bool _isChecking = false;
  String? _statusMessage;
  bool _isHealthy = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = CaregiverApiService.instance.currentServerUrl;
    _testHealth(_urlController.text);
  }

  Future<void> _testHealth(String url) async {
    setState(() {
      _isChecking = true;
      _statusMessage = null;
    });

    final healthy = await CaregiverApiService.instance.checkHealth(url.trim());
    if (mounted) {
      setState(() {
        _isChecking = false;
        _isHealthy = healthy;
        _statusMessage = healthy ? '🟢 Máy chủ sẵn sàng (Healthy)' : '🔴 Không thể kết nối máy chủ';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.dns, color: Color(0xFF0284C7)),
          SizedBox(width: 8),
          Text('Cấu Hình Máy Chủ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn kênh kết nối tới Backend Kestrel:',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildPresetButton(
              title: 'Cáp USB (Cục bộ)',
              subtitle: CaregiverApiService.defaultUsbUrl,
              icon: Icons.usb,
              url: CaregiverApiService.defaultUsbUrl,
            ),
            const SizedBox(height: 8),
            _buildPresetButton(
              title: 'Internet Cloudflare',
              subtitle: CaregiverApiService.defaultInternetUrl,
              icon: Icons.cloud,
              url: CaregiverApiService.defaultInternetUrl,
            ),
            const SizedBox(height: 8),
            _buildPresetButton(
              title: 'Mạng Wi-Fi Cục Bộ',
              subtitle: CaregiverApiService.defaultWifiUrl,
              icon: Icons.wifi,
              url: CaregiverApiService.defaultWifiUrl,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'URL Máy Chủ',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _testHealth(_urlController.text),
                ),
              ),
              onChanged: (val) => _testHealth(val),
            ),
            const SizedBox(height: 8),
            if (_isChecking)
              const Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Đang kiểm tra kết nối...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              )
            else if (_statusMessage != null)
              Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _isHealthy ? Colors.green[700] : Colors.red[700],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
          onPressed: () async {
            await CaregiverApiService.instance.setServerUrl(_urlController.text.trim());
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Lưu & Áp Dụng', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildPresetButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required String url,
  }) {
    final isSelected = _urlController.text.trim() == url.trim();
    return InkWell(
      onTap: () {
        _urlController.text = url;
        _testHealth(url);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0F2FE) : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : Colors.grey[300]!,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? const Color(0xFF0284C7) : Colors.grey[700]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, fontSize: 13)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[600]), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
