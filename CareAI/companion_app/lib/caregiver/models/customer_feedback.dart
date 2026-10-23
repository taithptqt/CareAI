class CustomerFeedback {
  final String id, category, subject, message;
  final DateTime createdAt;
  final String status;
  final String? adminReply;
  final DateTime? repliedAt;
  const CustomerFeedback(
    this.id,
    this.category,
    this.subject,
    this.message,
    this.createdAt, {
    this.status = 'New',
    this.adminReply,
    this.repliedAt,
  });
  factory CustomerFeedback.fromJson(Map<String, dynamic> json) =>
      CustomerFeedback(
        json['id'] as String,
        json['category'] as String,
        json['subject'] as String,
        json['message'] as String,
        DateTime.parse(json['createdAtUtc'] as String),
        status: json['status'] as String? ?? 'New',
        adminReply: json['adminReply'] as String?,
        repliedAt: json['repliedAtUtc'] is String
            ? DateTime.parse(json['repliedAtUtc'] as String)
            : null,
      );
  static String categoryLabel(String value) => switch (value) {
    'Bug' => 'Báo lỗi',
    'Suggestion' => 'Đề xuất cải tiến',
    _ => 'Góp ý khác',
  };
}

class FeedbackPage {
  final List<CustomerFeedback> items;
  final int page, totalCount, pageSize;
  const FeedbackPage(this.items, this.page, this.totalCount, this.pageSize);
  factory FeedbackPage.fromJson(Map<String, dynamic> json) => FeedbackPage(
    (json['items'] as List)
        .map((item) => CustomerFeedback.fromJson(item as Map<String, dynamic>))
        .toList(),
    json['page'] as int,
    json['totalCount'] as int,
    json['pageSize'] as int,
  );
}
