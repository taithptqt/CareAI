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
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
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
        if (_selectedElderId == null && elders.isNotEmpty) {
          _selectedElderId = elders.first.id;
          _selectedElderName = elders.first.fullName;
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
      final pagedResult = await CaregiverApiService.instance.getElderIncidentHistory(
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Lịch Sử Sự Cố & Cứu Hộ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF0284C7),
        foregroundColor: Colors.white,
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
          _buildFilterBar(),
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
          // 1. Chọn Người cao tuổi (nếu có nhiều cụ)
          if (_elders.length > 1 || _selectedElderId != null) ...[
            Row(
              children: [
                const Icon(Icons.person_outline, size: 20, color: Color(0xFF0284C7)),
                const SizedBox(width: 8),
                const Text('Người cao tuổi:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF475569))),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedElderId,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF0284C7)),
                        items: _elders.map((elder) {
                          return DropdownMenuItem<String>(
                            value: elder.id,
                            child: Text(
                              elder.fullName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (newId) {
                          if (newId != null && newId != _selectedElderId) {
                            final chosen = _elders.firstWhere((e) => e.id == newId);
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
                _statusFilterChip('🔴 Đang mở', 1),
                const SizedBox(width: 8),
                _statusFilterChip('🟡 Đã tiếp nhận', 2),
                const SizedBox(width: 8),
                _statusFilterChip('🟢 Đã giải quyết', 3),
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
      selectedColor: const Color(0xFFE0F2FE),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF475569),
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
      selectedColor: const Color(0xFFE2E8F0),
      labelStyle: TextStyle(
        fontSize: 11,
        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (selected) {
        setState(() => _selectedEmergencyType = selected ? typeValue : null);
        _onFilterChanged();
      },
    );
  }

  Widget _buildSummaryStats() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFF1F5F9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Tổng cộng: $_totalCount sự cố${_selectedElderName.isNotEmpty && _selectedElderName != 'Tất cả' ? ' ($_selectedElderName)' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
          ),
          if (_totalPages > 1)
            Text(
              'Trang $_currentPage / $_totalPages',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 12),
            Text('Đang tải lịch sử sự cố...', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_toggle_off, size: 48, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Không Có Sự Cố Nào',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              const Text(
                'Không tìm thấy sự cố nào phù hợp với bộ lọc đã chọn.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
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
    if (upper.contains('FALL')) return Icons.personal_injury_rounded;
    if (upper.contains('OXYGEN') || upper.contains('SPO2')) return Icons.air_rounded;
    if (upper.contains('TACHYCARDIA') || upper.contains('BRADYCARDIA') || upper.contains('SURGE') || upper.contains('HR') || upper.contains('HEART')) return Icons.monitor_heart_rounded;
    if (upper.contains('HYPERTENSION') || upper.contains('BLOOD_PRESSURE')) return Icons.speed_rounded;
    if (upper.contains('STALE') || upper.contains('OFFLINE')) return Icons.signal_cellular_connected_no_internet_4_bar_rounded;
    if (upper.contains('SOS')) return Icons.emergency_rounded;
    return Icons.crisis_alert_rounded;
  }

  String _emergencyLabel(String type) {
    final upper = type.toUpperCase();
    if (upper.contains('FALL')) return 'Té ngã';
    if (upper.contains('LOW_OXYGEN') || upper.contains('LOWOXYGEN') || upper.contains('OXYGEN')) return 'Oxy máu thấp';
    if (upper.contains('TACHYCARDIA') || upper.contains('CRITICAL_HIGH_HR')) return 'Nhịp tim nhanh';
    if (upper.contains('BRADYCARDIA') || upper.contains('CRITICAL_LOW_HR')) return 'Nhịp tim chậm';
    if (upper.contains('SURGE')) return 'Nhịp tim tăng vọt';
    if (upper.contains('HYPERTENSION')) return 'Cơn tăng huyết áp';
    if (upper.contains('STALE') || upper.contains('OFFLINE')) return 'Mất tín hiệu';
    if (upper.contains('SOS')) return 'Nút khẩn cấp SOS';
    return type;
  }

  Widget _buildIncidentCard(Incident incident) {
    final isOpen = incident.isOpen;
    final isAck = incident.isAcknowledged;
    final isResolved = incident.isResolved;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isOpen) {
      statusColor = const Color(0xFFDC2626);
      statusText = 'Đang Mở';
      statusIcon = Icons.warning_amber_rounded;
    } else if (isAck) {
      statusColor = const Color(0xFFD97706);
      statusText = 'Đã Tiếp Nhận';
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = const Color(0xFF16A34A);
      statusText = 'Đã Giải Quyết';
      statusIcon = Icons.task_alt;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: isOpen ? 2 : 1,
      color: isOpen ? const Color(0xFFFEF2F2) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IncidentDetailScreen(incident: incident)),
          );
          _loadPage(_currentPage, append: false);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Loại khẩn cấp, Mức độ, Huy hiệu trạng thái
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    child: Icon(
                      _emergencyIcon(incident.emergencyType),
                      color: statusColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_emergencyLabel(incident.emergencyType)} · ${incident.elderName}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          DateFormat('HH:mm:ss dd/MM/yyyy').format(incident.triggeredAt.toLocal()),
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              // Thông tin tiếp nhận hoặc giải quyết
              if (isAck && incident.acknowledgedAt != null) ...[
                Row(
                  children: [
                    const Icon(Icons.person_pin, size: 14, color: Color(0xFFD97706)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Tiếp nhận lúc: ${DateFormat('HH:mm:ss dd/MM').format(incident.acknowledgedAt!.toLocal())}',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ],

              if (isResolved && incident.resolvedAt != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified, size: 14, color: Color(0xFF16A34A)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Giải quyết lúc: ${DateFormat('HH:mm:ss dd/MM').format(incident.resolvedAt!.toLocal())}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF14532D), fontWeight: FontWeight.w600),
                          ),
                          if (incident.resolutionNotes?.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Ghi chú: "${incident.resolutionNotes}"',
                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF475569)),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],

              // Sinh hiệu tóm tắt nếu có snapshot
              if (incident.snapshot != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (incident.snapshot?.heartRateBpm != null)
                      _miniVital('Nhịp tim', '${incident.snapshot!.heartRateBpm!.toStringAsFixed(0)} bpm', Icons.favorite),
                    if (incident.snapshot?.spO2Percent != null)
                      _miniVital('SpO₂', '${incident.snapshot!.spO2Percent!.toStringAsFixed(0)}%', Icons.air),
                    if (incident.snapshot?.bpSystolic != null && incident.snapshot?.bpDiastolic != null)
                      _miniVital('Huyết áp', '${incident.snapshot!.bpSystolic!.toInt()}/${incident.snapshot!.bpDiastolic!.toInt()}', Icons.speed),
                  ],
                ),
              ],

              const SizedBox(height: 10),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Xem chi tiết & biểu đồ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7))),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: Color(0xFF0284C7)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniVital(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
      ],
    );
  }
}
