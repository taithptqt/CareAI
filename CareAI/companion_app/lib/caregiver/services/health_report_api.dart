import 'dart:convert';
import 'package:http/http.dart' as http;
import 'caregiver_api_service.dart';

abstract class HealthReportApi {
  Future<Map<String, dynamic>> get(String elderId, String resource, {int? beforeId});
}

class HttpHealthReportApi implements HealthReportApi {
  @override
  Future<Map<String, dynamic>> get(String elderId, String resource, {int? beforeId}) async {
    final session = CaregiverApiService.instance;
    final token = await session.getToken();
    // Health data must only go to the configured server; no automatic host failover.
    final uri = Uri.parse('${session.currentServerUrl}/api/v1/elders/${Uri.encodeComponent(elderId)}/health/$resource')
        .replace(queryParameters: beforeId == null ? null : {'beforeId': '$beforeId'});
    final response = await http.get(uri, headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401) throw Exception('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
    if (response.statusCode == 403) throw Exception('Bạn không còn quyền xem hồ sơ này.');
    if (response.statusCode != 200) throw Exception('Không thể tải dữ liệu. Vui lòng thử lại.');
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}
