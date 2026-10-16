import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/health_report_api.dart';

DateTime _utc(dynamic value) {
  final text = value as String;
  return DateTime.parse(RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(text) ? text : '${text}Z');
}

String _date(dynamic value) => DateFormat('dd/MM/yyyy').format(_utc(value).toLocal());

class HealthCornerScreen extends StatelessWidget {
  final String elderId;
  final HealthReportApi? api;
  const HealthCornerScreen({super.key, required this.elderId, this.api});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(title: const Text('Góc Sức Khỏe AI'), bottom: const TabBar(
        tabs: [Tab(text: 'Nhận định'), Tab(text: 'Báo cáo tuần')],
      )),
      body: TabBarView(children: [
        _HealthHistory(elderId: elderId, api: api ?? HttpHealthReportApi(), reports: false),
        _HealthHistory(elderId: elderId, api: api ?? HttpHealthReportApi(), reports: true),
      ]),
    ),
  );
}

class _HealthHistory extends StatefulWidget {
  final String elderId;
  final HealthReportApi api;
  final bool reports;
  const _HealthHistory({required this.elderId, required this.api, required this.reports});
  @override
  State<_HealthHistory> createState() => _HealthHistoryState();
}

class _HealthHistoryState extends State<_HealthHistory> with AutomaticKeepAliveClientMixin {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  int? _next;
  @override
  bool get wantKeepAlive => true;
  @override
  void initState() { super.initState(); _load(true); }

  Future<void> _load(bool reset) async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final page = await widget.api.get(widget.elderId, widget.reports ? 'weekly-reports' : 'insights', beforeId: reset ? null : _next);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll((page['items'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _next = (page['nextBeforeId'] as num?)?.toInt();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: () => _load(true),
      child: ListView(padding: const EdgeInsets.all(16), physics: const AlwaysScrollableScrollPhysics(), children: [
        const Text('Cùng gia đình theo dõi và hỏi thăm người thân', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Nhận định hỗ trợ theo dõi, không thay thế chẩn đoán của nhân viên y tế.'),
        const SizedBox(height: 16),
        if (_items.isEmpty && !_loading && _error == null)
          Padding(padding: const EdgeInsets.all(24), child: Text(widget.reports
            ? 'Chưa có báo cáo tuần. Báo cáo được cập nhật vào sáng Chủ Nhật.'
            : 'Chưa có nhận định bất thường. Hệ thống cần đủ dữ liệu để phân tích.')),
        ..._items.map((item) => widget.reports ? _report(item) : _insight(item)),
        if (_error != null) ...[
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextButton(onPressed: () => _load(_items.isEmpty), child: const Text('Thử lại')),
        ],
        if (_loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!_loading && _next != null)
          OutlinedButton(onPressed: () => _load(false), child: const Text('Xem các tuần trước / nhận định cũ')),
      ]),
    );
  }

  Widget _report(Map<String, dynamic> item) {
    final isGemini = item['source'] == 'GEMINI';
    return Card(
      elevation: 0.8,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isGemini ? const Color(0xFFEEF2FF) : const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isGemini ? Icons.auto_awesome_rounded : Icons.article_rounded,
            color: isGemini ? const Color(0xFF6366F1) : const Color(0xFF0284C7),
          ),
        ),
        title: Text(
          'Tuần từ ${_date(item['weekStartUtc'])}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Đến trước ${_date(item['weekEndUtc'])} • ${isGemini ? 'AI hỗ trợ tổng kết' : 'Tổng kết theo số liệu'}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyReportDetailScreen(
          elderId: widget.elderId, reportId: (item['id'] as num).toInt(), api: widget.api,
        ))),
      ),
    );
  }

  Widget _insight(Map<String, dynamic> item) {
    final heart = item['insightType'] == 'NIGHT_HEART_RATE_SPIKE';
    final value = (item['observedValue'] as num).toStringAsFixed(0);
    final baseline = (item['baselineValue'] as num).toStringAsFixed(0);
    return Card(
      elevation: 0.8,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: heart ? const Color(0xFFFEE2E2) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    heart ? Icons.favorite_rounded : Icons.directions_walk_rounded,
                    color: heart ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heart ? 'Nhịp tim ban đêm tăng' : 'Buổi sáng chưa ghi nhận bước đi',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _date(item['windowEndUtc']),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                heart
                    ? 'Trung bình đêm: $value nhịp/phút; mức thường ngày: $baseline.'
                    : 'Ghi nhận $value bước; mức buổi sáng thường ngày: $baseline.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              heart
                  ? 'Hãy hỏi xem ông/bà ngủ có ngon không, có cảm thấy khó chịu không; trao đổi với nhân viên y tế nếu có lo ngại.'
                  : 'Hãy hỏi thăm sinh hoạt buổi sáng và kiểm tra xem ông/bà có đeo thiết bị đúng cách không.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class ParsedWeeklyReport {
  final String overview;
  final String observations;
  final String advice;
  final String disclaimer;
  final String? avgHeartRate;
  final String? avgDailySteps;
  final String? avgSpo2;
  final String? alertCount;

  bool get hasAnyMetric =>
      avgHeartRate != null || avgDailySteps != null || avgSpo2 != null || alertCount != null;

  ParsedWeeklyReport({
    required this.overview,
    required this.observations,
    required this.advice,
    required this.disclaimer,
    this.avgHeartRate,
    this.avgDailySteps,
    this.avgSpo2,
    this.alertCount,
  });

  factory ParsedWeeklyReport.fromContent(String fullContent) {
    String overview = '';
    String observations = '';
    String advice = '';
    String disclaimer = 'Báo cáo hỗ trợ theo dõi, không phải chẩn đoán y khoa.';

    final sec1Idx = fullContent.indexOf(RegExp(r'1\.\s*Tổng quan', caseSensitive: false));
    final sec2Idx = fullContent.indexOf(RegExp(r'2\.\s*Điểm tích cực', caseSensitive: false));
    final sec3Idx = fullContent.indexOf(RegExp(r'3\.\s*Lời khuyên', caseSensitive: false));
    final discIdx = fullContent.indexOf(RegExp(r'Báo cáo hỗ trợ theo dõi', caseSensitive: false));

    if (sec1Idx != -1) {
      final start1 = fullContent.indexOf('\n', sec1Idx);
      final end1 = sec2Idx != -1 ? sec2Idx : (discIdx != -1 ? discIdx : fullContent.length);
      overview = (start1 != -1 && start1 < end1)
          ? fullContent.substring(start1, end1).trim()
          : fullContent.substring(sec1Idx, end1).trim();

      if (sec2Idx != -1) {
        final start2 = fullContent.indexOf('\n', sec2Idx);
        final end2 = sec3Idx != -1 ? sec3Idx : (discIdx != -1 ? discIdx : fullContent.length);
        observations = (start2 != -1 && start2 < end2)
            ? fullContent.substring(start2, end2).trim()
            : '';
      }

      if (sec3Idx != -1) {
        final start3 = fullContent.indexOf('\n', sec3Idx);
        final end3 = discIdx != -1 ? discIdx : fullContent.length;
        advice = (start3 != -1 && start3 < end3)
            ? fullContent.substring(start3, end3).trim()
            : '';
      }
    } else {
      overview = fullContent.trim();
    }

    String? hr;
    final hrMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:nhịp/phút|bpm)', caseSensitive: false).firstMatch(fullContent);
    if (hrMatch != null) hr = hrMatch.group(1);

    String? steps;
    final stepsMatch = RegExp(r'(?:trung bình\s+)?(\d+(?:[.,]\d+)?)\s*bước', caseSensitive: false).firstMatch(fullContent);
    if (stepsMatch != null) steps = stepsMatch.group(1);

    String? spo2;
    final spo2Match = RegExp(r'SpO[2₂].*?(\d{2,3}(?:[.,]\d+)?)\s*%', caseSensitive: false).firstMatch(fullContent);
    if (spo2Match != null) spo2 = spo2Match.group(1);

    String? alerts;
    final alertMatch = RegExp(r'(\d+)\s*nhận định bất thường', caseSensitive: false).firstMatch(fullContent);
    if (alertMatch != null) {
      alerts = alertMatch.group(1);
    } else if (fullContent.contains('chưa ghi nhận nhận định bất thường')) {
      alerts = '0';
    }

    return ParsedWeeklyReport(
      overview: overview,
      observations: observations,
      advice: advice,
      disclaimer: disclaimer,
      avgHeartRate: hr,
      avgDailySteps: steps,
      avgSpo2: spo2,
      alertCount: alerts,
    );
  }
}

class WeeklyReportDetailScreen extends StatefulWidget {
  final String elderId;
  final int reportId;
  final HealthReportApi api;
  const WeeklyReportDetailScreen({super.key, required this.elderId, required this.reportId, required this.api});
  @override
  State<WeeklyReportDetailScreen> createState() => _WeeklyReportDetailScreenState();
}

class _WeeklyReportDetailScreenState extends State<WeeklyReportDetailScreen> {
  late Future<Map<String, dynamic>> _report;
  @override
  void initState() { super.initState(); _report = _fetch(); }
  Future<Map<String, dynamic>> _fetch() => widget.api.get(widget.elderId, 'weekly-reports/${widget.reportId}');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Báo cáo sức khỏe tuần'),
      elevation: 0,
    ),
    body: FutureBuilder<Map<String, dynamic>>(future: _report, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Không thể tải báo cáo.'),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _report = _fetch()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ]));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final report = snapshot.data!;
      final rawContent = report['content'] as String;
      final isGemini = report['source'] == 'GEMINI';
      final parsed = ParsedWeeklyReport.fromContent(rawContent);

      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header Card Tuần & Nguồn AI
            _buildHeaderCard(report, isGemini),
            const SizedBox(height: 16),

            // 2. Liếc nhanh 3 giây (Quick Glance KPI Grid)
            if (parsed.hasAnyMetric) ...[
              _buildQuickGlanceSection(parsed),
              const SizedBox(height: 16),
            ],

            // 3. Card: 1. Tổng quan sức khỏe tuần
            _buildSectionCard(
              title: '1. Tổng quan sức khỏe tuần',
              content: parsed.overview.isNotEmpty ? parsed.overview : rawContent,
              icon: Icons.monitor_heart_rounded,
              iconColor: const Color(0xFF0284C7),
              borderColor: const Color(0xFFBAE6FD),
              bgColor: const Color(0xFFF0F9FF),
            ),
            const SizedBox(height: 14),

            // 4. Card: 2. Điểm tích cực & Cần lưu ý
            if (parsed.observations.isNotEmpty) ...[
              _buildSectionCard(
                title: '2. Điểm tích cực & Cần lưu ý',
                content: parsed.observations,
                icon: Icons.lightbulb_rounded,
                iconColor: const Color(0xFFD97706),
                borderColor: const Color(0xFFFDE68A),
                bgColor: const Color(0xFFFFFBEB),
              ),
              const SizedBox(height: 14),
            ],

            // 5. Card: 3. Lời khuyên sinh hoạt tuần tới
            if (parsed.advice.isNotEmpty) ...[
              _buildSectionCard(
                title: '3. Lời khuyên sinh hoạt tuần tới',
                subtitle: 'Gợi ý hỏi thăm & trao đổi cùng ông/bà',
                content: parsed.advice,
                icon: Icons.family_restroom_rounded,
                iconColor: const Color(0xFF6366F1),
                borderColor: const Color(0xFFC7D2FE),
                bgColor: const Color(0xFFEEF2FF),
              ),
              const SizedBox(height: 14),
            ],

            // 6. Medical Disclaimer Card
            _buildDisclaimerCard(parsed.disclaimer),
            const SizedBox(height: 20),
          ],
        ),
      );
    }),
  );

  Widget _buildHeaderCard(Map<String, dynamic> report, bool isGemini) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isGemini ? const Color(0xFF4F46E5).withOpacity(0.25) : const Color(0xFF0284C7).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isGemini ? const Color(0xFF818CF8) : const Color(0xFF38BDF8),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGemini ? Icons.auto_awesome_rounded : Icons.fact_check_outlined,
                      size: 13,
                      color: isGemini ? const Color(0xFFA5B4FC) : const Color(0xFF7DD3FC),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isGemini ? 'Gemini 2.5 Flash AI' : 'Hệ thống quy tắc CareAI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isGemini ? const Color(0xFFA5B4FC) : const Color(0xFF7DD3FC),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.calendar_month_rounded, size: 16, color: Colors.white70),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tuần từ ${_date(report['weekStartUtc'])}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          if (report['weekEndUtc'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Đến trước ${_date(report['weekEndUtc'])}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickGlanceSection(ParsedWeeklyReport parsed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.bolt_rounded, size: 17, color: Color(0xFFF59E0B)),
            SizedBox(width: 6),
            Text(
              'TÓM TẮT NHANH TRONG TUẦN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (parsed.avgHeartRate != null)
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.favorite_rounded,
                  iconColor: const Color(0xFFEF4444),
                  label: 'Nhịp tim TB',
                  value: '${parsed.avgHeartRate} bpm',
                  bgColor: const Color(0xFFFEF2F2),
                ),
              ),
            if (parsed.avgHeartRate != null && parsed.avgDailySteps != null)
              const SizedBox(width: 8),
            if (parsed.avgDailySteps != null)
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.directions_walk_rounded,
                  iconColor: const Color(0xFF10B981),
                  label: 'Vận động TB',
                  value: '${parsed.avgDailySteps} bước',
                  bgColor: const Color(0xFFECFDF5),
                ),
              ),
          ],
        ),
        if (parsed.avgSpo2 != null || parsed.alertCount != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              if (parsed.avgSpo2 != null)
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.air_rounded,
                    iconColor: const Color(0xFF0284C7),
                    label: 'SpO₂ trung bình',
                    value: '${parsed.avgSpo2}%',
                    bgColor: const Color(0xFFF0F9FF),
                  ),
                ),
              if (parsed.avgSpo2 != null && parsed.alertCount != null)
                const SizedBox(width: 8),
              if (parsed.alertCount != null)
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.warning_amber_rounded,
                    iconColor: parsed.alertCount == '0' ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    label: 'Nhận định lưu ý',
                    value: parsed.alertCount == '0' ? 'Ổn định' : '${parsed.alertCount} lần',
                    bgColor: parsed.alertCount == '0' ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: iconColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required String content,
    required IconData icon,
    required Color iconColor,
    required Color borderColor,
    required Color bgColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: iconColor,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: iconColor.withOpacity(0.8),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              content,
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimerCard(String disclaimer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              disclaimer,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
