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

  Widget _report(Map<String, dynamic> item) => Card(child: ListTile(
    leading: const Icon(Icons.article_outlined),
    title: Text('Tuần từ ${_date(item['weekStartUtc'])}'),
    subtitle: Text('Đến trước ${_date(item['weekEndUtc'])} • ${item['source'] == 'GEMINI' ? 'AI hỗ trợ tổng kết' : 'Tổng kết theo số liệu'}'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyReportDetailScreen(
      elderId: widget.elderId, reportId: (item['id'] as num).toInt(), api: widget.api,
    ))),
  ));

  Widget _insight(Map<String, dynamic> item) {
    final heart = item['insightType'] == 'NIGHT_HEART_RATE_SPIKE';
    final value = (item['observedValue'] as num).toStringAsFixed(0);
    final baseline = (item['baselineValue'] as num).toStringAsFixed(0);
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(heart ? Icons.favorite_outline : Icons.directions_walk), const SizedBox(width: 8),
          Expanded(child: Text(heart ? 'Nhịp tim ban đêm tăng' : 'Buổi sáng chưa ghi nhận bước đi', style: const TextStyle(fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 8), Text(_date(item['windowEndUtc'])),
        const SizedBox(height: 8),
        Text(heart ? 'Trung bình đêm: $value nhịp/phút; mức thường ngày: $baseline.' : 'Ghi nhận $value bước; mức buổi sáng thường ngày: $baseline.'),
        const SizedBox(height: 8),
        Text(heart ? 'Hãy hỏi xem người cao tuổi ngủ có ngon không, có cảm thấy khó chịu không; trao đổi với nhân viên y tế nếu có lo ngại.'
          : 'Hãy hỏi thăm sinh hoạt buổi sáng và kiểm tra xem người cao tuổi có đeo thiết bị đúng cách không.'),
      ],
    )));
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
    appBar: AppBar(title: const Text('Báo cáo sức khỏe tuần')),
    body: FutureBuilder<Map<String, dynamic>>(future: _report, builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Không thể tải báo cáo.'),
          TextButton(onPressed: () => setState(() => _report = _fetch()), child: const Text('Thử lại')),
        ]));
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final report = snapshot.data!;
      return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tuần từ ${_date(report['weekStartUtc'])}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16), SelectableText(report['content'] as String, style: const TextStyle(fontSize: 17, height: 1.6)),
        ],
      ));
    }),
  );
}
