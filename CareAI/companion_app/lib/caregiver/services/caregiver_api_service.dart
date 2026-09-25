import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class CaregiverApiService {
  static final CaregiverApiService instance = CaregiverApiService._init();
  CaregiverApiService._init();

  static const String defaultUsbUrl = 'http://127.0.0.1:5097';
  static const String defaultInternetUrl = 'https://recording-arthur-widely-bald.trycloudflare.com';
  static const String defaultWifiUrl = 'http://192.168.0.105:5097';

  String _currentServerUrl = defaultUsbUrl;
  String get currentServerUrl => _currentServerUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _currentServerUrl = prefs.getString('caregiver_server_url') ?? defaultUsbUrl;
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _currentServerUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caregiver_server_url', normalized);
  }

  // Quản lý Token JWT
  Future<void> saveAuth(AuthResponse auth) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', auth.token);
    await prefs.setString('caregiver_id', auth.caregiverId);
    await prefs.setString('caregiver_name', auth.fullName);
    await prefs.setString('caregiver_email', auth.email);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<String?> getCaregiverId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('caregiver_id');
  }

  Future<String?> getCaregiverName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('caregiver_name');
  }

  Future<String?> getCaregiverEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('caregiver_email');
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('caregiver_id');
    await prefs.remove('caregiver_name');
    await prefs.remove('caregiver_email');
  }

  Map<String, String> _buildHeaders(String? token) {
    final headers = {
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Cơ chế Chuyển mạch Dự phòng Đa kênh (Dual-Network Failover)
  Future<http.Response> _executeWithFailover(
    Future<http.Response> Function(String baseUrl) action,
  ) async {
    try {
      return await action(_currentServerUrl);
    } catch (_) {
      final fallbackUrls = [defaultUsbUrl, defaultInternetUrl]
          .where((u) => u != _currentServerUrl)
          .toList();
      for (final altUrl in fallbackUrls) {
        try {
          final res = await action(altUrl);
          _currentServerUrl = altUrl;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('caregiver_server_url', altUrl);
          return res;
        } catch (_) {}
      }
      rethrow;
    }
  }

  // 1. Kiểm tra sức khỏe máy chủ (/health)
  Future<bool> checkHealth([String? targetUrl]) async {
    final url = targetUrl ?? _currentServerUrl;
    try {
      final response = await http
          .get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200 && response.body.contains('Healthy');
    } catch (_) {
      return false;
    }
  }

  // 2. Đăng ký tài khoản Người thân (UC-01)
  Future<AuthResponse> register({
    required String fullName,
    required String phoneNumber,
    required String email,
    required String password,
  }) async {
    final body = jsonEncode({
      'fullName': fullName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/register'),
          headers: _buildHeaders(null),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      final auth = AuthResponse.fromJson(data);
      await saveAuth(auth);
      return auth;
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Đăng ký thất bại (Mã lỗi: ${response.statusCode})');
    }
  }

  // 3. Đăng nhập Người thân (UC-01)
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final body = jsonEncode({
      'email': email.trim().toLowerCase(),
      'password': password,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: _buildHeaders(null),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final auth = AuthResponse.fromJson(data);
      await saveAuth(auth);
      return auth;
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Email hoặc mật khẩu không chính xác');
    }
  }

  // 4. Danh sách Người cao tuổi đang chăm sóc (UC-02 / UC-10)
  Future<List<ElderItem>> getMyElders() async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/caregivers/elders'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => ElderItem.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
    } else {
      throw Exception('Không thể tải danh sách người cao tuổi (${response.statusCode})');
    }
  }

  // 5. Tạo Hồ sơ Người cao tuổi mới (UC-02)
  Future<ElderItem> createElder({
    required String fullName,
    required DateTime dateOfBirth,
    String? medicalNotes,
    String? emergencyContact,
    String? homeAddress,
    double? homeLatitude,
    double? homeLongitude,
  }) async {
    final token = await getToken();
    final body = jsonEncode({
      'fullName': fullName.trim(),
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'medicalNotes': medicalNotes?.trim(),
      'emergencyContact': emergencyContact?.trim(),
      'homeAddress': homeAddress?.trim(),
      'homeLatitude': homeLatitude,
      'homeLongitude': homeLongitude,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/caregivers/elders'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 201) {
      return ElderItem.fromJson(jsonDecode(response.body));
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Tạo hồ sơ thất bại (${response.statusCode})');
    }
  }

  // 6. Sinh mã PIN 6 số ghép nối thiết bị (UC-02)
  Future<String> generatePin(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/devices/generate-pin/$elderProfileId'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['pin'] ?? '';
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Không thể sinh mã PIN (${response.statusCode})');
    }
  }

  // 7. Bảng điều khiển Sức khỏe Trực tiếp của Cụ (UC-10)
  Future<ElderDashboard> getElderDashboard(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return ElderDashboard.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải bảng điều khiển sức khỏe (${response.statusCode})');
    }
  }

  // 7.1. Lấy dữ liệu biến thiên nhịp tim 24h phục vụ biểu đồ (Nhiệm vụ 1.4)
  Future<HeartRate24hData> getHeartRate24h(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId/vitals/heart-rate-24h'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return HeartRate24hData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải chuỗi nhịp tim 24h (${response.statusCode})');
    }
  }

  // 7.2. Lấy dữ liệu lịch sử biến thiên huyết áp 14 ngày (Gói A)
  Future<BloodPressureHistoryData> getBloodPressureHistory(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId/vitals/blood-pressure-history'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return BloodPressureHistoryData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải lịch sử huyết áp (${response.statusCode})');
    }
  }

  // 7.3. Lấy dữ liệu SpO2 24h & đếm số cơn tụt oxy (Gói A)
  Future<Spo224hData> getSpo224h(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId/vitals/spo2-24h'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return Spo224hData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải chuỗi SpO2 24h (${response.statusCode})');
    }
  }

  // 7.4. Lấy phân bố số bước vận động theo 24 giờ trong ngày (Gói A)
  Future<HourlyStepsData> getHourlySteps24h(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId/vitals/hourly-steps-24h'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return HourlyStepsData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải dữ liệu vận động 24h (${response.statusCode})');
    }
  }

  // 7.5. Lấy tổng kết giấc ngủ đêm & thời lượng sâu/nông (Gói B)
  Future<SleepSummaryData> getElderSleepSummary(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/dashboard/elder/$elderProfileId/vitals/sleep-summary'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return SleepSummaryData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Không thể tải tổng kết giấc ngủ (${response.statusCode})');
    }
  }

  // 8. Danh sách Sự cố Đang mở / Đã tiếp nhận (UC-08 Quorum Alerting)
  Future<List<Incident>> getActiveIncidents() async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/incidents/active'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 6)));

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => Incident.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      throw Exception('Không thể tải sự cố khẩn cấp (${response.statusCode})');
    }
  }

  Future<void> updateElderHomeAddress(String elderId, String address,
      {double? latitude, double? longitude}) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http.put(
      Uri.parse('$baseUrl/api/v1/caregivers/elders/${Uri.encodeComponent(elderId)}/home-address'),
      headers: _buildHeaders(token),
      body: jsonEncode({
        'homeAddress': address.trim(),
        'homeLatitude': latitude,
        'homeLongitude': longitude,
      }),
    ).timeout(const Duration(seconds: 10)));
    if (response.statusCode != 200) {
      throw Exception('Không thể lưu địa chỉ nhà (${response.statusCode})');
    }
  }

  Future<Incident> getIncident(String id) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http.get(
      Uri.parse('$baseUrl/api/v1/incidents/${Uri.encodeComponent(id)}'),
      headers: _buildHeaders(token),
    ).timeout(const Duration(seconds: 8)));
    if (response.statusCode == 200) {
      return Incident.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(_extractError(response.body).isNotEmpty
        ? _extractError(response.body) : 'Không thể tải sự cố (${response.statusCode})');
  }

  Future<Uint8List?> getIncidentPhoto(String id) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http.get(
      Uri.parse('$baseUrl/api/v1/incidents/${Uri.encodeComponent(id)}/photo'),
      headers: _buildHeaders(token),
    ).timeout(const Duration(seconds: 8)));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('Không thể tải ảnh sự cố (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  Future<void> registerPushToken(String pushToken) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    final response = await _executeWithFailover((baseUrl) => http.post(
      Uri.parse('$baseUrl/api/v1/caregivers/push-token'),
      headers: _buildHeaders(token),
      body: jsonEncode({'pushToken': pushToken, 'deviceModel': 'Android caregiver app'}),
    ).timeout(const Duration(seconds: 8)));
    if (response.statusCode != 200) {
      throw Exception('Không thể đăng ký thông báo (${response.statusCode})');
    }
  }

  Future<void> unregisterPushToken(String pushToken) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return;
    final response = await _executeWithFailover((baseUrl) => http.delete(
      Uri.parse('$baseUrl/api/v1/caregivers/push-token'),
      headers: _buildHeaders(token),
      body: jsonEncode({'pushToken': pushToken}),
    ).timeout(const Duration(seconds: 8)));
    if (response.statusCode != 204) {
      throw Exception('Không thể hủy đăng ký thông báo (${response.statusCode})');
    }
  }

  // 9. Tiếp nhận Cứu hộ (UC-08 Human-in-the-Loop Acknowledge)
  Future<void> acknowledgeIncident(Incident incident, [String? notes]) async {
    final rowVersion = incident.rowVersion;
    if (rowVersion == null || rowVersion.isEmpty) {
      throw Exception('Thiếu phiên bản sự cố. Vui lòng tải lại danh sách trước khi tiếp nhận.');
    }
    final token = await getToken();
    final body = jsonEncode({
      'notes': notes ?? 'Đang trên đường đến hỗ trợ',
      'rowVersion': rowVersion,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/incidents/${incident.id}/acknowledge'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 409) {
      throw Exception(_extractError(response.body));
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Tiếp nhận sự cố thất bại (${response.statusCode})');
    }
  }

  // 10. Đóng sự cố Cứu hộ An toàn (UC-08 Resolve)
  Future<void> resolveIncident(Incident incident, String resolutionNotes) async {
    final rowVersion = incident.rowVersion;
    if (rowVersion == null || rowVersion.isEmpty) {
      throw Exception('Thiếu phiên bản sự cố. Vui lòng tải lại danh sách trước khi đóng.');
    }
    final token = await getToken();
    final body = jsonEncode({
      'resolutionNotes': resolutionNotes.trim(),
      'rowVersion': rowVersion,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/incidents/${incident.id}/resolve'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Đóng sự cố thất bại (${response.statusCode})');
    }
  }

  // 11. Lấy ngưỡng nhịp tim an toàn hiện tại (Nhiệm vụ 1.5)
  Future<ThresholdData> getElderThresholds(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/elders/$elderProfileId/thresholds'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return ThresholdData.fromJson(jsonDecode(response.body));
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Không thể lấy thông tin ngưỡng (${response.statusCode})');
    }
  }

  // 12. Phân tích gợi ý dải ngưỡng thích nghi 14 ngày (Nhiệm vụ 1.5)
  Future<ThresholdRecommendation> getThresholdRecommendation(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/elders/$elderProfileId/thresholds/recommendation'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 15)));

    if (response.statusCode == 200) {
      return ThresholdRecommendation.fromJson(jsonDecode(response.body));
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Không thể phân tích ngưỡng thích nghi (${response.statusCode})');
    }
  }

  // 13. Cập nhật dải ngưỡng thích nghi mới & làm mới cache tức thì (Nhiệm vụ 1.5 & Gói B)
  Future<ThresholdData> updateElderThresholds(
    String elderProfileId,
    double minBpm,
    double maxBpm, {
    double? nightMinBpm,
    double? nightMaxBpm,
    String? sleepStart,
    String? sleepEnd,
  }) async {
    final token = await getToken();
    final Map<String, dynamic> payload = {
      'restingHeartRateMin': minBpm,
      'restingHeartRateMax': maxBpm,
    };
    if (nightMinBpm != null) payload['nightHeartRateMin'] = nightMinBpm;
    if (nightMaxBpm != null) payload['nightHeartRateMax'] = nightMaxBpm;
    if (sleepStart != null && sleepStart.isNotEmpty) payload['sleepWindowStart'] = sleepStart;
    if (sleepEnd != null && sleepEnd.isNotEmpty) payload['sleepWindowEnd'] = sleepEnd;

    final body = jsonEncode(payload);

    final response = await _executeWithFailover((baseUrl) => http
        .put(
          Uri.parse('$baseUrl/api/v1/elders/$elderProfileId/thresholds'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return ThresholdData.fromJson(jsonDecode(response.body));
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Cập nhật ngưỡng thất bại (${response.statusCode})');
    }
  }

  // 14. Lịch sử sự cố và phân trang an toàn (BOLA + Pagination + Multi-field Filter)
  Future<PagedIncidents> getElderIncidentHistory(
    String elderProfileId, {
    int page = 1,
    int pageSize = 20,
    String? emergencyType,
    int? severity,
    int? status,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    final token = await getToken();
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (emergencyType != null && emergencyType.isNotEmpty) {
      queryParams['emergencyType'] = emergencyType;
    }
    if (severity != null) {
      queryParams['severity'] = severity.toString();
    }
    if (status != null) {
      queryParams['status'] = status.toString();
    }
    if (fromUtc != null) {
      queryParams['fromUtc'] = fromUtc.toIso8601String();
    }
    if (toUtc != null) {
      queryParams['toUtc'] = toUtc.toIso8601String();
    }

    final response = await _executeWithFailover((baseUrl) {
      final requestUri = Uri.parse('$baseUrl/api/v1/elders/${Uri.encodeComponent(elderProfileId)}/incidents')
          .replace(queryParameters: queryParams);
      return http.get(requestUri, headers: _buildHeaders(token)).timeout(const Duration(seconds: 10));
    });

    if (response.statusCode == 200) {
      return PagedIncidents.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Không thể tải lịch sử sự cố (${response.statusCode})');
    }
  }

  // 15. Chuỗi nhịp tim T-15..T+15 phút quanh sự cố
  Future<IncidentHeartRateWindow> getIncidentHeartRateSeries(String incidentId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http.get(
      Uri.parse('$baseUrl/api/v1/incidents/${Uri.encodeComponent(incidentId)}/heart-rate-series'),
      headers: _buildHeaders(token),
    ).timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return IncidentHeartRateWindow.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Không thể tải chuỗi nhịp tim sự cố (${response.statusCode})');
    }
  }

  String _extractError(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      return data['error'] ?? data['message'] ?? '';
    } catch (_) {
      return responseBody;
    }
  }
}

