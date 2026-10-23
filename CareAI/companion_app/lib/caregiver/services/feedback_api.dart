import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/customer_feedback.dart';
import 'caregiver_api_service.dart';

class FeedbackApiException implements Exception {
  final String message;
  const FeedbackApiException(this.message);
  @override
  String toString() => message;
}

class FeedbackApi {
  final http.Client _client;
  FeedbackApi({http.Client? client}) : _client = client ?? http.Client();
  void dispose() => _client.close();
  final CaregiverApiService _auth = CaregiverApiService.instance;
  Future<Map<String, dynamic>> _request({
    Map<String, String>? body,
    int page = 1,
  }) async {
    final token = await _auth.getToken();
    if (token == null || token.isEmpty) {
      throw const FeedbackApiException(
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      );
    }
    final base = _auth.currentServerUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      body == null
          ? '$base/api/v1/caregivers/feedback?page=$page'
          : '$base/api/v1/caregivers/feedback',
    );
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    try {
      // Keep the selected backend: a customer message must not fail over to another database.
      final response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401 || response.statusCode == 403) {
        unawaited(_auth.logout());
        _auth.sessionExpiredNotifier.value = true;
        throw const FeedbackApiException(
          'Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.',
        );
      }
      if (response.statusCode == 429) {
        throw const FeedbackApiException(
          'Bạn đã gửi nhiều phản hồi. Vui lòng chờ rồi thử lại.',
        );
      }
      if (response.statusCode == 409) {
        throw const FeedbackApiException(
          'Mã gửi đã được dùng cho nội dung khác. Mở lại màn hình để gửi góp ý mới.',
        );
      }
      if (response.statusCode == 400) {
        throw const FeedbackApiException(
          'Nội dung chưa hợp lệ. Kiểm tra tiêu đề và mô tả.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FeedbackApiException(
          'Dịch vụ phản hồi chưa sẵn sàng. Vui lòng thử lại sau.',
        );
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } on TimeoutException {
      throw const FeedbackApiException(
        'Chưa xác nhận được kết quả do kết nối chậm. Bạn có thể thử lại với cùng nội dung.',
      );
    } on http.ClientException {
      throw const FeedbackApiException(
        'Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.',
      );
    } on FormatException {
      throw const FeedbackApiException(
        'Máy chủ trả dữ liệu không hợp lệ. Vui lòng thử lại sau.',
      );
    }
  }

  Future<FeedbackPage> mine(int page) async =>
      FeedbackPage.fromJson(await _request(page: page));
  Future<CustomerFeedback> submit({
    required String requestId,
    required String category,
    required String subject,
    required String message,
  }) async => CustomerFeedback.fromJson(
    await _request(
      body: {
        'requestId': requestId,
        'category': category,
        'subject': subject,
        'message': message,
      },
    ),
  );
}
