import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';

class ElderEditDialog extends StatefulWidget {
  final ElderItem elder;
  final VoidCallback onUpdated;
  final VoidCallback onDeleted;

  const ElderEditDialog({
    super.key,
    required this.elder,
    required this.onUpdated,
    required this.onDeleted,
  });

  @override
  State<ElderEditDialog> createState() => _ElderEditDialogState();
}

class _ElderEditDialogState extends State<ElderEditDialog> {
  late TextEditingController _nameController;
  late TextEditingController _notesController;
  late TextEditingController _phoneController;
  late DateTime _selectedDob;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.elder.fullName);
    _notesController = TextEditingController(text: widget.elder.medicalNotes ?? '');
    _phoneController = TextEditingController(text: widget.elder.emergencyContact ?? '');
    _selectedDob = widget.elder.dateOfBirth;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Họ tên không được để trống.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await CaregiverApiService.instance.updateElder(
        widget.elder.id,
        fullName: _nameController.text.trim(),
        dateOfBirth: _selectedDob,
        medicalNotes: _notesController.text.trim(),
        emergencyContact: _phoneController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật hồ sơ Cụ thành công!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  Future<void> _confirmDeleteElder() async {
    final passwordController = TextEditingController();
    String? dialogError;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('XÓA HỒ SƠ CỤ', style: TextStyle(color: Color(0xFFDC2626), fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CẢNH BÁO AN TOÀN:\nHành động này sẽ xóa mềm hồ sơ Cụ "${widget.elder.fullName}", ẩn danh hóa toàn bộ thông tin cá nhân (PII), ngắt kết nối mọi thiết bị và giải tán nhóm chăm sóc gia đình.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vui lòng nhập mật khẩu tài khoản của bạn để xác thực cấp 2:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu tài khoản cấp 2',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Text(dialogError!, style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final pwd = passwordController.text.trim();
                if (pwd.isEmpty) {
                  setDState(() => dialogError = 'Vui lòng nhập mật khẩu.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Xác Nhận Xóa'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final pwd = passwordController.text.trim();
      setState(() => _isLoading = true);
      try {
        await CaregiverApiService.instance.deleteElder(widget.elder.id, pwd);
        if (mounted) {
          Navigator.pop(context);
          widget.onDeleted();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hồ sơ đã được xóa mềm và ẩn danh hóa an toàn.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString().replaceAll('Exception:', '').trim();
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Chỉnh Sửa Hồ Sơ Cụ',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 12),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Text(_errorMessage!, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
                  ),

                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Họ và tên Cụ *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  title: Text(
                    'Ngày sinh: ${DateFormat('dd/MM/yyyy').format(_selectedDob)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 20, color: Color(0xFF0284C7)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDob,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _selectedDob = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Tiền sử bệnh lý', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'SĐT khẩn cấp', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isLoading ? null : _saveChanges,
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),

                // Danger Zone
                const Text(
                  'VÙNG NGUY HIỂM (PRIMARY CAREGIVER)',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFDC2626), letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),

                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Xóa mềm hồ sơ & Ẩn danh hóa PII'),
                  onPressed: _isLoading ? null : _confirmDeleteElder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
