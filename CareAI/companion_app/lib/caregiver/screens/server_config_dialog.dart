import 'package:flutter/material.dart';

import '../services/caregiver_api_service.dart';
import '../../services/api_service.dart';
import '../../theme/careai_theme.dart';
import '../../widgets/careai_ui.dart';

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
    final initialUrl = CaregiverApiService.instance.currentServerUrl.isNotEmpty
        ? CaregiverApiService.instance.currentServerUrl
        : ApiService.instance.activeServerUrl;
    _urlController.text = initialUrl;
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
        _statusMessage = healthy
            ? 'Máy chủ sẵn sàng'
            : 'Không thể kết nối máy chủ';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.dns, color: Color(0xFF4A3020)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kết nối máy chủ',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn kết nối CareAI hoặc nhập địa chỉ máy chủ riêng.',
              style: TextStyle(fontSize: 14, color: CareAiColors.secondary),
            ),
            const SizedBox(height: 12),
            _buildPresetButton(
              title: 'Máy chủ đám mây',
              subtitle: CaregiverApiService.defaultInternetUrl,
              icon: Icons.cloud,
              url: CaregiverApiService.defaultInternetUrl,
            ),
            const SizedBox(height: 8),
            _buildPresetButton(
              title: 'Cáp USB',
              subtitle: CaregiverApiService.defaultUsbUrl,
              icon: Icons.usb,
              url: CaregiverApiService.defaultUsbUrl,
            ),
            const SizedBox(height: 8),
            _buildPresetButton(
              title: 'Wi-Fi cục bộ',
              subtitle: CaregiverApiService.defaultWifiUrl,
              icon: Icons.wifi,
              url: CaregiverApiService.defaultWifiUrl,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Địa chỉ máy chủ',
                suffixIcon: IconButton(
                  tooltip: 'Kiểm tra kết nối',
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
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang kiểm tra kết nối...',
                      style: TextStyle(
                        fontSize: 13,
                        color: CareAiColors.secondary,
                      ),
                    ),
                  ),
                ],
              )
            else if (_statusMessage != null)
              CareAiStatusLabel(
                label: _statusMessage!,
                icon: _isHealthy
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                color: _isHealthy ? CareAiColors.greenInk : CareAiColors.danger,
                background: _isHealthy
                    ? CareAiColors.greenSurface
                    : CareAiColors.dangerSurface,
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
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4A3020),
          ),
          onPressed: () async {
            final targetUrl = _urlController.text.trim();
            await CaregiverApiService.instance.setServerUrl(targetUrl);
            await ApiService.instance.setServerUrl(targetUrl);
            if (context.mounted) Navigator.pop(context, true);
          },
          child: const Text(
            'Lưu kết nối',
            style: TextStyle(color: Colors.white),
          ),
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
    return Semantics(
      selected: isSelected,
      button: true,
      child: InkWell(
        onTap: () {
          _urlController.text = url;
          _testHealth(url);
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected
                ? CareAiColors.greenSurface
                : CareAiColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? CareAiColors.sage : CareAiColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? const Color(0xFF4A3020) : Colors.grey[700],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CareAiColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_rounded,
                  color: CareAiColors.greenInk,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
