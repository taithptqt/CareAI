import '../../theme/careai_theme.dart';
import '../../widgets/careai_ui.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/caregiver_api_service.dart';
import 'incident_detail_screen.dart';

class IncidentHistoryScreen extends StatefulWidget {
  final String? initialElderProfileId;
  final String? initialElderName;

  const IncidentHistoryScreen({
    super.key,
    this.initialElderProfileId,
    this.initialElderName,
  });

  @override
  State<IncidentHistoryScreen> createState() => _IncidentHistoryScreenState();
}

class _IncidentHistoryScreenState extends State<IncidentHistoryScreen> {
  List<ElderItem> _elders = [];
  String? _selectedElderId;
  String _selectedElderName = 'Tất cả';

  // Bộ lọc
  int? _selectedStatus; // null: Tất cả, 1: Open, 2: Acknowledged, 3: Resolved
  String? _selectedEmergencyType; // null: Tất cả, FALL, MANUAL_SOS, etc.
  int? _selectedSeverity; // null: Tất cả, 3: Critical, 2: Warning, 1: Info

  // Trạng thái phân trang
  int _currentPage = 1;
  static const int _pageSize = 15;
  int _totalPages = 1;
  int _totalCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;

  List<Incident> _incidents = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _selectedElderId = widget.initialElderProfileId;
    _selectedElderName = widget.initialElderName ?? 'Tất cả';
    _scrollController.addListener(_onScroll);
    _initData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isLoadingMore && _currentPage < _totalPages) {
        _loadPage(_currentPage + 1, append: true);
      }
    }
  }

  Future<void> _initData() async {
    try {
      final elders = await CaregiverApiService.instance.getMyElders();
      if (!mounted) return;
      setState(() {
        _elders = elders;
        final stillExists = elders.any((e) => e.id == _selectedElderId);
        if ((_selectedElderId == null || !stillExists) && elders.isNotEmpty) {
          _selectedElderId = elders.first.id;
          _selectedElderName = elders.first.fullName;
        } else if (elders.isEmpty) {
          _selectedElderId = null;
          _selectedElderName = 'Tất cả';
        }
      });
    } catch (_) {}

    await _loadPage(1, append: false);
  }

  Future<void> _loadPage(int page, {required bool append}) async {
    if (_selectedElderId == null) {
      setState(() {
        _incidents = [];
        _totalCount = 0;
        _totalPages = 1;
        _isLoading = false;
        _isLoadingMore = false;
      });
      return;
    }

    if (append) {
      setState(() => _isLoadingMore = true);
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final pagedResult = await CaregiverApiService.instance
          .getElderIncidentHistory(
            _selectedElderId!,
            page: page,
            pageSize: _pageSize,
            emergencyType: _selectedEmergencyType,
            severity: _selectedSeverity,
            status: _selectedStatus,
          );

      if (!mounted) return;

      setState(() {
        _currentPage = pagedResult.page;
        _totalPages = pagedResult.totalPages > 0 ? pagedResult.totalPages : 1;
        _totalCount = pagedResult.totalCount;
        if (append) {
          _incidents.addAll(pagedResult.items);
          _isLoadingMore = false;
        } else {
          _incidents = pagedResult.items;
          _isLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onFilterChanged() {
    _loadPage(1, append: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF7F2),
      appBar: AppBar(
        title: const Text('Lịch sử chăm sóc'),
        backgroundColor: CareAiColors.canvas,
        foregroundColor: CareAiColors.ink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () => _loadPage(1, append: false),
          ),
        ],
      ),
      body: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.36,
            ),
            child: SingleChildScrollView(child: _buildFilterBar()),
          ),
          _buildSummaryStats(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Chọn Người cao tuổi (nếu có nhiều người)
          if (_elders.length > 1 || _selectedElderId != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 20,
                      color: Color(0xFF4A3020),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Người cao tuổi:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF6E6259),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2ECE4),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE4DACD)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedElderId,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Color(0xFF4A3020),
                      ),
                      items: _elders.map((elder) {
                        return DropdownMenuItem<String>(
                          value: elder.id,
                          child: Text(
                            elder.fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newId) {
                        if (newId != null && newId != _selectedElderId) {
                          final chosen = _elders.firstWhere(
                            (e) => e.id == newId,
                          );
                          setState(() {
                            _selectedElderId = newId;
                            _selectedElderName = chosen.fullName;
                          });
                          _onFilterChanged();
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // 2. Chips Lọc Trạng thái
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _statusFilterChip('Tất cả trạng thái', null),
                const SizedBox(width: 8),
                _statusFilterChip('Đang mở', 1),
                const SizedBox(width: 8),
                _statusFilterChip('Đã tiếp nhận', 2),
                const SizedBox(width: 8),
                _statusFilterChip('Đã giải quyết', 3),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 3. Chips Lọc Loại sự cố
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _typeFilterChip('Tất cả loại', null),
                const SizedBox(width: 6),
                _typeFilterChip('Té Ngã', 'FALL'),
                const SizedBox(width: 6),
                _typeFilterChip('Nút SOS', 'MANUAL_SOS'),
                const SizedBox(width: 6),
                _typeFilterChip('Oxy thấp (SpO₂)', 'LOW_OXYGEN'),
                const SizedBox(width: 6),
                _typeFilterChip('Nhịp tim ≥180', 'CRITICAL_HIGH_HR'),
                const SizedBox(width: 6),
                _typeFilterChip('Nhịp tim ≤35', 'CRITICAL_LOW_HR'),
                const SizedBox(width: 6),
                _typeFilterChip('Mất tín hiệu', 'STALE_OFFLINE'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusFilterChip(String label, int? statusValue) {
    final isSelected = _selectedStatus == statusValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: CareAiColors.brown,
      showCheckmark: false,
      shape: const StadiumBorder(),
      side: const BorderSide(color: CareAiColors.border),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : CareAiColors.brown,
      ),
      onSelected: (selected) {
        setState(() => _selectedStatus = statusValue);
        _onFilterChanged();
      },
    );
  }

  Widget _typeFilterChip(String label, String? typeValue) {
    final isSelected = _selectedEmergencyType == typeValue;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: CareAiColors.sageLight,
      shape: const StadiumBorder(),
      side: const BorderSide(color: CareAiColors.border),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isSelected ? const Color(0xFF231811) : const Color(0xFF7D7168),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (selected) {
        setState(() => _selectedEmergencyType = selected ? typeValue : null);
        _onFilterChanged();
      },
    );
  }

  Widget _buildSummaryStats() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _selectedElderName.isNotEmpty && _selectedElderName != 'Tất cả'
              ? _selectedElderName
              : 'Các sự cố trong gia đình',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: CareAiColors.ink,
          ),
        ),
        const SizedBox(height: 7),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(
              _isLoading
                  ? 'Đang cập nhật lịch sử…'
                  : '$_totalCount sự cố phù hợp bộ lọc',
              style: const TextStyle(
                fontSize: 13,
                color: CareAiColors.secondary,
              ),
            ),
            if (_totalPages > 1)
              Text(
                'Trang $_currentPage / $_totalPages',
                style: const TextStyle(
                  fontSize: 13,
                  color: CareAiColors.secondary,
                ),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 12),
            Text(
              'Đang tải lịch sử sự cố...',
              style: TextStyle(fontSize: 13, color: Color(0xFF7D7168)),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Thử Lại'),
                onPressed: () => _loadPage(1, append: false),
              ),
            ],
          ),
        ),
      );
    }

    if (_incidents.isEmpty) {
      return const CareAiEmptyState(
        icon: Icons.history_rounded,
        title: 'Chưa có sự cố phù hợp',
        description: 'Lịch sử đã ghi nhận sẽ xuất hiện tại đây. Bạn có thể chọn bộ lọc khác để xem lại.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadPage(1, append: false),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _incidents.length + (_currentPage < _totalPages ? 1 : 0),
        itemBuilder: (ctx, index) {
          if (index == _incidents.length) {
            return _buildLoadMoreFooter();
          }

          final incident = _incidents[index];
          return _buildIncidentCard(incident);
        },
      ),
    );
  }

  Widget _buildLoadMoreFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: OutlinedButton.icon(
        icon: const Icon(Icons.arrow_downward, size: 16),
        label: Text('Tải thêm trang ${_currentPage + 1} / $_totalPages'),
        onPressed: () => _loadPage(_currentPage + 1, append: true),
      ),
    );
  }

  IconData _emergencyIcon(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return Icons.warning_rounded;
    if (upper.contains('OXYGEN') || upper.contains('SPO2')) {
      return Icons.air_rounded;
    }
    if (upper.contains('TACHYCARDIA') ||
        upper.contains('BRADYCARDIA') ||
        upper.contains('SURGE') ||
        upper.contains('HR') ||
        upper.contains('HEART')) {
      return Icons.monitor_heart_rounded;
    }
    if (upper.contains('HYPERTENSION') || upper.contains('BLOOD_PRESSURE')) {
      return Icons.speed_rounded;
    }
    if (upper.contains('STALE') || upper.contains('OFFLINE')) {
      return Icons.wifi_off_rounded;
    }
    if (upper.contains('SOS')) return Icons.emergency_rounded;
    return Icons.crisis_alert_rounded;
  }

  String _emergencyLabel(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return 'Té ngã';
    if (upper.contains('LOW_OXYGEN') ||
        upper.contains('LOWOXYGEN') ||
        upper.contains('OXYGEN')) {
      return 'Oxy máu thấp';
    }
    if (upper.contains('TACHYCARDIA') || upper.contains('CRITICAL_HIGH_HR')) {
      return 'Nhịp tim nhanh';
    }
    if (upper.contains('BRADYCARDIA') || upper.contains('CRITICAL_LOW_HR')) {
      return 'Nhịp tim chậm';
    }
    if (upper.contains('SURGE')) return 'Nhịp tim tăng vọt';
    if (upper.contains('HYPERTENSION')) return 'Cơn tăng huyết áp';
    if (upper.contains('STALE') || upper.contains('OFFLINE')) {
      return 'Mất tín hiệu';
    }
    if (upper.contains('SOS')) return 'Nút khẩn cấp SOS';
    return type;
  }

  Widget _buildIncidentCard(Incident incident) {
    final isOpen = incident.isOpen;
    final isAck = incident.isAcknowledged;
    final isResolved = incident.isResolved;
    final color = isOpen
        ? CareAiColors.danger
        : isAck
        ? CareAiColors.amber
        : CareAiColors.greenInk;
    final status = isOpen
        ? 'Chưa tiếp nhận'
        : isAck
        ? 'Đã tiếp nhận'
        : 'Đã giải quyết';
    final statusIcon = isOpen
        ? Icons.notification_important_outlined
        : isAck
        ? Icons.check_circle_outline_rounded
        : Icons.task_alt_rounded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncidentDetailScreen(incident: incident),
              ),
            );
            _loadPage(_currentPage, append: false);
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _emergencyIcon(incident.emergencyType),
                        size: 22,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            incident.elderName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: CareAiColors.ink,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _emergencyLabel(incident.emergencyType),
                            style: const TextStyle(
                              fontSize: 14,
                              color: CareAiColors.brown,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            DateFormat('HH:mm · dd/MM/yyyy')
                                .format(incident.triggeredAt.toLocal()),
                            style: const TextStyle(
                              fontSize: 12,
                              color: CareAiColors.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: CareAiColors.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CareAiStatusLabel(
                  label: status,
                  icon: statusIcon,
                  color: color,
                ),
                if (isAck && incident.acknowledgedAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Tiếp nhận lúc ${DateFormat('HH:mm · dd/MM').format(incident.acknowledgedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CareAiColors.secondary,
                    ),
                  ),
                ],
                if (isResolved && incident.resolvedAt != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Hoàn tất lúc ${DateFormat('HH:mm · dd/MM').format(incident.resolvedAt!.toLocal())}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CareAiColors.greenInk,
                    ),
                  ),
                  if (incident.resolutionNotes?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(
                      incident.resolutionNotes!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: CareAiColors.secondary,
                      ),
                    ),
                  ],
                ],
                if (incident.snapshot != null) ...[
                  const Divider(),
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    children: [
                      if (incident.snapshot?.heartRateBpm != null)
                        _miniVital(
                          'Nhịp tim',
                          '${incident.snapshot!.heartRateBpm!.toStringAsFixed(0)} bpm',
                          Icons.favorite_outline_rounded,
                        ),
                      if (incident.snapshot?.spO2Percent != null)
                        _miniVital(
                          'SpO₂',
                          '${incident.snapshot!.spO2Percent!.toStringAsFixed(0)}%',
                          Icons.air_rounded,
                        ),
                      if (incident.snapshot?.bpSystolic != null &&
                          incident.snapshot?.bpDiastolic != null)
                        _miniVital(
                          'Huyết áp',
                          '${incident.snapshot!.bpSystolic!.toInt()}/${incident.snapshot!.bpDiastolic!.toInt()}',
                          Icons.speed_rounded,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniVital(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF7D7168)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Color(0xFF7D7168)),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF231811),
          ),
        ),
      ],
    );
  }
}
