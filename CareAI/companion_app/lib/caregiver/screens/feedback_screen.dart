import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/careai_theme.dart';
import '../models/customer_feedback.dart';
import '../services/feedback_api.dart';

class FeedbackScreen extends StatefulWidget {
  final FeedbackApi? api;
  const FeedbackScreen({super.key, this.api});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  late final FeedbackApi _api;
  String _category = 'Suggestion';
  String? _requestId, _payload, _sendError, _loadError, _confirmation;
  bool _sending = false, _loading = true;
  FeedbackPage? _history;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? FeedbackApi();
    _load(1);
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _load(int page) async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final history = await _api.mine(page);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _history = history);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(
        () => _loadError = error is FeedbackApiException
            ? error.message
            : 'Không tải được lịch sử phản hồi. Vui lòng thử lại.',
      );
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_sending || !_form.currentState!.validate()) return;
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    final payload = '$_category\u0000$subject\u0000$message';
    if (_requestId == null || _payload != payload) {
      final random = Random.secure();
      _requestId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      _payload = payload;
    }
    setState(() {
      _sending = true;
      _sendError = null;
      _confirmation = null;
    });
    try {
      final receipt = await _api.submit(
        requestId: _requestId!,
        category: _category,
        subject: subject,
        message: message,
      );
      if (!mounted) return;
      setState(() {
        _confirmation = 'Đã nhận phản hồi. Mã: ${receipt.id}';
        _subject.clear();
        _message.clear();
        _requestId = null;
        _payload = null;
      });
      FocusManager.instance.primaryFocus?.unfocus();
      await _load(1);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _sendError = error is FeedbackApiException
            ? error.message
            : 'Chưa xác nhận gửi thành công. Nội dung được giữ để bạn thử lại.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Góp ý & phản hồi')),
    body: SafeArea(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: RefreshIndicator(
        onRefresh: () => _load(_history?.page ?? 1),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Giúp CareAI chăm sóc tốt hơn',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          const Text(
            'Gửi lỗi gặp phải hoặc đề xuất của bạn. Đây không phải kênh SOS và không được theo dõi khẩn cấp. Không gửi mật khẩu, mã ghép đôi hoặc thông tin sức khỏe nhạy cảm.',
          ),
          const SizedBox(height: 20),
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Loại phản hồi'),
                  items: const [
                    DropdownMenuItem(
                      value: 'Suggestion',
                      child: Text('Đề xuất cải tiến'),
                    ),
                    DropdownMenuItem(value: 'Bug', child: Text('Báo lỗi')),
                    DropdownMenuItem(value: 'Other', child: Text('Góp ý khác')),
                  ],
                  onChanged: _sending
                      ? null
                      : (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _subject,
                  enabled: !_sending,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Tiêu đề',
                    hintText: 'Bạn muốn góp ý về điều gì?',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => (value?.trim().length ?? 0) < 3
                      ? 'Nhập ít nhất 3 ký tự.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _message,
                  enabled: !_sending,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 3000,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung',
                    alignLabelWithHint: true,
                    hintText: 'Mô tả vấn đề, cách gặp lỗi hoặc điều bạn muốn cải thiện.',
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (value) => (value?.trim().length ?? 0) < 10
                      ? 'Mô tả ít nhất 10 ký tự.'
                      : null,
                ),
                if (_sendError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _sendError!,
                        style: const TextStyle(color: CareAiColors.danger),
                      ),
                    ),
                  ),
                if (_confirmation != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _confirmation!,
                        style: const TextStyle(color: CareAiColors.greenInk),
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _sending ? null : _submit,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_sending ? 'Đang gửi…' : 'Gửi phản hồi'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Phản hồi của bạn',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Tải lại phản hồi',
                onPressed: _loading ? null : () => _load(_history?.page ?? 1),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '$_loadError${_history != null ? ' Danh sách dưới đây chưa được cập nhật.' : ''}',
                style: const TextStyle(color: CareAiColors.danger),
              ),
            ),
          if (!_loading && _loadError == null && _history?.totalCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Bạn chưa gửi phản hồi nào.'),
            ),
          for (final item in _history?.items ?? <CustomerFeedback>[])
            Card(
              child: ExpansionTile(
                title: Text(item.subject),
                subtitle: Text(
                  '${CustomerFeedback.categoryLabel(item.category)} · ${DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt.toLocal())}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(item.message),
                  const SizedBox(height: 12),
                  Text(
                    item.status == 'Resolved'
                        ? 'Đã phản hồi'
                        : item.status == 'InProgress'
                        ? 'Đang xử lý'
                        : 'Đã nhận góp ý',
                  ),
                  if (item.adminReply != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'CareAI trả lời',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    SelectableText(item.adminReply!),
                    if (item.repliedAt != null)
                      Text(
                        DateFormat('dd/MM/yyyy HH:mm')
                            .format(item.repliedAt!.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Mã: ${item.id}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (_history != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_history!.totalCount} phản hồi · Trang ${_history!.page}',
                  ),
                ),
                IconButton(
                  tooltip: 'Trang trước',
                  onPressed: _loading || _history!.page <= 1
                      ? null
                      : () => _load(_history!.page - 1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Trang sau',
                  onPressed:
                      _loading ||
                          _history!.page * _history!.pageSize >=
                              _history!.totalCount
                      ? null
                      : () => _load(_history!.page + 1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    ),
  ),
      ),
);
}
