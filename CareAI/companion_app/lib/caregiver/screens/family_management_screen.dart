import '../../theme/careai_theme.dart';
import '../../widgets/careai_ui.dart';

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
      final members = await CaregiverApiService.instance.getFamilyMembers(
        widget.elderId,
      );
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
    final current = _members
        .where((m) => m.caregiverId == _currentCaregiverId)
        .toList();
    if (current.isEmpty) return false;
    return current.first.isPrimary;
  }

  Future<void> _generateInviteCode() async {
    try {
      final res = await CaregiverApiService.instance.createFamilyInvitation(
        widget.elderId,
      );
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          decoration: const BoxDecoration(
            color: CareAiColors.canvas,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 48,
                    color: Color(0xFF4A3020),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mời gia đình cùng chăm sóc',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF231811),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Gửi mã 6 ký tự này cho người thân để cùng chăm sóc ${widget.elderName}:',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7D7168),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4E4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF4A3020),
                        width: 2,
                      ),
                    ),
                    child: SelectableText(
                      res.invitationCode,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing:
                            MediaQuery.textScalerOf(ctx).scale(28) > 42 ? 0 : 4,
                        color: Color(0xFF4A3020),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Color(0xFF8C7A6B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Hết hạn lúc: ${DateFormat('HH:mm - dd/MM/yyyy').format(res.expiresAt.toLocal())}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8C7A6B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stacked =
                          MediaQuery.textScalerOf(context).scale(14) > 20;
                      final buttonWidth = stacked
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 12) / 2;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: buttonWidth,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('Sao chép mã'),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: res.invitationCode),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Đã sao chép mã mời vào bộ nhớ tạm!',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            width: buttonWidth,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4A3020),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: const StadiumBorder(),
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Xong'),
                              onPressed: () => Navigator.pop(ctx),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
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

  Future<void> _confirmSelfLeave(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời Nhóm Chăm Sóc'),
        content: Text(
          'Bạn có chắc chắn muốn rời khỏi nhóm chăm sóc ${widget.elderName}?\nBạn sẽ không còn nhận được các cảnh báo cấp cứu và không thể theo dõi sức khỏe của Cụ nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CareAiColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời Nhóm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await CaregiverApiService.instance.revokeFamilyMember(
          widget.elderId,
          member.caregiverId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bạn đã rời khỏi nhóm chăm sóc thành công.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
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

  Future<void> _confirmRevokeMember(FamilyMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thu Hồi Quyền Chăm Sóc'),
        content: Text(
          'Bạn có chắc chắn muốn thu hồi quyền của "${member.fullName}" khỏi nhóm chăm sóc ${widget.elderName}?\nThành viên này sẽ không thể theo dõi chỉ số hay nhận cảnh báo nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thu Hồi Quyền'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await CaregiverApiService.instance.revokeFamilyMember(
          widget.elderId,
          member.caregiverId,
        );
        _loadMembers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã thu hồi quyền của ${member.fullName}!'),
              backgroundColor: Colors.green,
            ),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Gia đình cùng chăm sóc'),
      actions: [
        IconButton(
          onPressed: _loadMembers,
          tooltip: 'Làm mới danh sách',
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(top: false, child: _buildBody()),
    bottomNavigationBar: _isCurrentUserPrimary
        ? SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: FilledButton.icon(
                onPressed: _generateInviteCode,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Mời người thân cùng chăm sóc'),
              ),
            ),
          )
        : null,
  );

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return CareAiEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Chưa tải được gia đình',
        description: _errorMessage!,
        action: FilledButton.icon(
          onPressed: _loadMembers,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Thử lại'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadMembers,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: CareAiColors.peach,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.family_restroom_rounded,
                  color: CareAiColors.brown,
                  size: 32,
                ),
                const SizedBox(height: 16),
                Text(
                  'Bên nhau chăm sóc',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.elderName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: CareAiColors.brown,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_members.length} người thân trong nhóm',
                  style: const TextStyle(
                    fontSize: 14,
                    color: CareAiColors.brown,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: CareAiColors.greenSurface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CareAiStatusLabel(
                  label: _isCurrentUserPrimary
                      ? 'Bạn là người chăm sóc chính'
                      : 'Bạn là người chăm sóc',
                  icon: _isCurrentUserPrimary
                      ? Icons.verified_user_outlined
                      : Icons.person_outline_rounded,
                  color: CareAiColors.greenInk,
                ),
                const SizedBox(height: 12),
                Text(
                  _isCurrentUserPrimary
                      ? 'Bạn có thể quản lý hồ sơ và mời người thân cùng theo dõi. Các thay đổi quyền vẫn cần xác nhận.'
                      : 'Bạn có thể xem thông tin sức khỏe, nhận cảnh báo và tiếp nhận sự cố của người cao tuổi.',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: CareAiColors.brown,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const CareAiSectionHeading('Những người đồng hành'),
          const SizedBox(height: 14),
          if (_members.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Chưa có thành viên để hiển thị.',
                style: TextStyle(color: CareAiColors.secondary),
              ),
            ),
          ..._members.map((member) {
            final isPrimary = member.isPrimary;
            final isMe = member.caregiverId == _currentCaregiverId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: isPrimary
                                ? CareAiColors.sageLight
                                : CareAiColors.lavender,
                            child: Text(
                              member.fullName.isEmpty
                                  ? '?'
                                  : member.fullName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: CareAiColors.brown,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.fullName + (isMe ? ' (Bạn)' : ''),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: CareAiColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                CareAiStatusLabel(
                                  label: isPrimary
                                      ? 'Chăm sóc chính'
                                      : 'Cùng chăm sóc',
                                  icon: isPrimary
                                      ? Icons.verified_outlined
                                      : Icons.people_outline_rounded,
                                  color: isPrimary
                                      ? CareAiColors.greenInk
                                      : CareAiColors.lavenderInk,
                                ),
                              ],
                            ),
                          ),
                          if (_isCurrentUserPrimary && !isPrimary && !isMe)
                            IconButton(
                              tooltip: 'Thu hồi quyền thành viên',
                              onPressed: () => _confirmRevokeMember(member),
                              icon: const Icon(
                                Icons.person_remove_outlined,
                                color: CareAiColors.danger,
                              ),
                            )
                          else if (isMe && !isPrimary)
                            IconButton(
                              tooltip: 'Rời nhóm chăm sóc',
                              onPressed: () => _confirmSelfLeave(member),
                              icon: const Icon(
                                Icons.logout_rounded,
                                color: CareAiColors.danger,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        member.email,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: CareAiColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        member.phoneNumber,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: CareAiColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tham gia ${DateFormat('dd/MM/yyyy').format(member.assignedAt.toLocal())}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CareAiColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
