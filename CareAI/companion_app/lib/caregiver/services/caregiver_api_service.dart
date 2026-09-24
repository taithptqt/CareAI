import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class CaregiverApiService {
  static final CaregiverApiService instance = CaregiverApiService._init();
  CaregiverApiService._init();

  static const String defaultUsbUrl = 'http://127.0.0.1:5097';
  static const String defaultInternetUrl = 'https://promote-continue-scholarships-guy.trycloudflare.com';
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
  }) async {
    final token = await getToken();
    final body = jsonEncode({
      'fullName': fullName.trim(),
      'dateOfBirth': dateOfBirth.toIso8601String(),
      'medicalNotes': medicalNotes?.trim(),
      'emergencyContact': emergencyContact?.trim(),
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

  // 9. Tiếp nhận Cứu hộ (UC-08 Human-in-the-Loop Acknowledge)
  Future<void> acknowledgeIncident(String incidentId, [String? notes]) async {
    final token = await getToken();
    final body = jsonEncode({
      'notes': notes ?? 'Đang trên đường đến hỗ trợ',
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/incidents/$incidentId/ack'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 409) {
      throw Exception('Sự cố vừa được cập nhật bởi một người thân khác.');
    } else {
      final err = _extractError(response.body);
      throw Exception(err.isNotEmpty ? err : 'Tiếp nhận sự cố thất bại (${response.statusCode})');
    }
  }

  // 10. Đóng sự cố Cứu hộ An toàn (UC-08 Resolve)
  Future<void> resolveIncident(String incidentId, String resolutionNotes) async {
    final token = await getToken();
    final body = jsonEncode({
      'resolutionNotes': resolutionNotes.trim(),
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/incidents/$incidentId/resolve'),
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

  String _extractError(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      return data['error'] ?? data['message'] ?? '';
    } catch (_) {
      return responseBody;
    }
  }
}
