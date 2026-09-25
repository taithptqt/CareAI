import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/caregiver_api_service.dart';

class FamilyManagementScreen extends StatefulWidget {
  final String elderId;
  final String elderName;

  const FamilyManagementScreen({
    super.key,
    required this.elderId,
    required this.elderName,
  });

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  List<FamilyMember> _members = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentCaregiverId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    _currentCaregiverId = await CaregiverApiService.instance.getCaregiverId();
    await _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final members = await CaregiverApiService.instance.getFamilyMembers(widget.elderId);
      if (mounted) {
        setState(() {
          _members = members;
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

  bool get _isCurrentUserPrimary {
    final current = _members.where((m) => m.caregiverId == _currentCaregiverId).toList();
    if (current.isEmpty) return false;
    return current.first.isPrimary;
  }

  Future<void> _generateInviteCode() async {
    try {
      final res = await CaregiverApiService.instance.createFamilyInvitation(widget.elderId);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              const Icon(Icons.mark_email_read_outlined, size: 48, color: Color(0xFF0284C7)),
              const SizedBox(height: 12),
              const Text(
                'Mã Mời Gia Đình 24 Giờ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              Text(
                'Gửi mã 6 ký tự này cho người thân để cùng chăm sóc Cụ ${widget.elderName}:',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF0284C7), width: 2),
                ),
                child: Text(
                  res.invitationCode,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer_outlined, size: 14, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    'Hết hạn lúc: ${DateFormat('HH:mm - dd/MM/yyyy').format(res.expiresAt.toLocal())}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Sao Chép Mã'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: res.invitationCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã sao chép mã mời vào bộ nhớ tạm!'), backgroundColor: Colors.green),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Xong'),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmRevokeMember(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thu Hồi Quyền Chăm Sóc'),
        content: Text(
          'Bạn có chắc chắn muốn thu hồi quyền của "${member.fullName}" khỏi nhóm chăm sóc Cụ ${widget.elderName}?\nThành viên này sẽ không thể theo dõi chỉ số hay nhận cảnh báo nữa.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thu Hồi Quyền'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await CaregiverApiService.instance.revokeFamilyMember(widget.elderId, member.caregiverId);
        _loadMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đã thu hồi quyền của ${member.fullName}!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Nhóm Gia Đình - ${widget.elderName}'),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _isCurrentUserPrimary
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.person_add),
              label: const Text('Mời Thành Viên (24h)'),
              onPressed: _generateInviteCode,
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC2626)),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFDC2626))),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadMembers, child: const Text('Thử Lại')),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Role Info Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            children: [
              Icon(
                _isCurrentUserPrimary ? Icons.admin_panel_settings : Icons.supervised_user_circle,
                color: const Color(0xFF0284C7),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCurrentUserPrimary
                          ? 'Bạn là Người Bảo Hộ Chính (Primary)'
                          : 'Bạn là Người Bảo Hộ Phụ (Secondary)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isCurrentUserPrimary
                          ? 'Bạn có toàn quyền chỉnh sửa hồ sơ, mời hoặc xóa thành viên, hủy ghép nối và xóa hồ sơ.'
                          : 'Bạn có quyền xem chỉ số, nhận cảnh báo cứu hộ khẩn cấp và tiếp nhận cứu trợ.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Thành Viên Trong Nhóm (${_members.length})',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 8),

        ..._members.map((member) {
          final isPrimary = member.isPrimary;
          final isMe = member.caregiverId == _currentCaregiverId;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isPrimary ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE),
                    child: Icon(
                      isPrimary ? Icons.star : Icons.person,
                      color: isPrimary ? const Color(0xFFD97706) : const Color(0xFF0284C7),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                member.fullName + (isMe ? ' (Bạn)' : ''),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPrimary ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isPrimary ? const Color(0xFFFDE68A) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                isPrimary ? 'Primary' : 'Secondary',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isPrimary ? const Color(0xFFB45309) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${member.email} • ${member.phoneNumber}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tham gia: ${DateFormat('dd/MM/yyyy').format(member.assignedAt.toLocal())}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),

                  // Nút xóa (chỉ Primary được xóa và không xóa chính mình)
                  if (_isCurrentUserPrimary && !isPrimary && !isMe)
                    IconButton(
                      icon: const Icon(Icons.person_remove_outlined, color: Color(0xFFDC2626)),
                      tooltip: 'Thu hồi quyền thành viên',
                      onPressed: () => _confirmRevokeMember(member),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
