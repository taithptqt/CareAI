import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../models/models.dart';

class CaregiverApiService {
  static final CaregiverApiService instance = CaregiverApiService._init();
  CaregiverApiService._init();

  final sessionExpiredNotifier = ValueNotifier<bool>(false);

  static const String defaultInternetUrl = ApiService.internetTunnelUrl;
  static const String defaultUsbUrl = ApiService.usbServerUrl;
  static const String defaultWifiUrl = ApiService.wifiServerUrl;

  String _currentServerUrl = defaultInternetUrl;
  String get currentServerUrl => _currentServerUrl;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isExplicit = prefs.getBool('caregiver_server_url_explicitly_set') ?? false;
    final saved = prefs.getString('caregiver_server_url');
    if (saved == null || (!isExplicit && saved == defaultUsbUrl)) {
      _currentServerUrl = defaultInternetUrl;
      await prefs.setString('caregiver_server_url', defaultInternetUrl);
    } else {
      _currentServerUrl = saved;
    }
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _currentServerUrl = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('caregiver_server_url', normalized);
    await prefs.setBool('caregiver_server_url_explicitly_set', true);
  }

  // Quản lý Token JWT
  Future<void> saveAuth(AuthResponse auth) async {
    final prefs = await SharedPreferences.getInstance();
    final previousCaregiverId = prefs.getString('previous_caregiver_id') ?? prefs.getString('caregiver_id');
    if (previousCaregiverId != null && previousCaregiverId.isNotEmpty && previousCaregiverId != auth.caregiverId) {
      // Đăng nhập bằng tài khoản Người thân khác -> Hủy thông tin ghép đôi của Người cao tuổi thuộc tài khoản cũ
      await ApiService.instance.unpair();
    }
    await prefs.setString('previous_caregiver_id', auth.caregiverId);
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
    final currentId = prefs.getString('caregiver_id');
    if (currentId != null && currentId.isNotEmpty) {
      await prefs.setString('previous_caregiver_id', currentId);
    }
    await prefs.remove('jwt_token');
    await prefs.remove('caregiver_id');
    await prefs.remove('caregiver_name');
    await prefs.remove('caregiver_email');
    await prefs.remove('caregiver_cached_elder_ids');
    await prefs.remove('careai_selected_role');
  }

  /// Kiểm tra tính sở hữu của phiên Người thân hiện tại với Người cao tuổi trên thiết bị.
  /// Nếu phiên Người thân hiện tại KHÔNG sở hữu Người cao tuổi này (hoặc phiên hết hạn/không hợp lệ),
  /// tự động đăng xuất an toàn (logout) và trả về false để điều hướng về LoginScreen.
  Future<bool> verifyOrLogoutIfMismatchedElder(String? currentElderProfileId) async {
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return false;
    if (currentElderProfileId == null || currentElderProfileId.isEmpty) {
      return true; // Thiết bị chưa ghép đôi Cụ nào, cho phép người thân vào HomeScreen
    }

    try {
      final elders = await getMyElders();
      final isOwner = elders.any((e) => e.id == currentElderProfileId);
      if (!isOwner) {
        // Người cao tuổi trên máy KHÔNG thuộc danh sách quản lý của tài khoản này
        // Đăng xuất phiên Người thân cũ để bảo vệ tính cô lập dữ liệu gia đình
        await logout();
        return false;
      }
      return true;
    } catch (e) {
      // Nếu gặp lỗi mạng, kiểm tra cache đã lưu của phiên đăng nhập hiện tại
      final prefs = await SharedPreferences.getInstance();
      final cachedIds = prefs.getStringList('caregiver_cached_elder_ids');
      if (cachedIds != null && cachedIds.contains(currentElderProfileId)) {
        return true;
      }
      // Không có trong cache hoặc session cũ không hợp lệ -> Đăng xuất để bảo đảm an toàn
      await logout();
      return false;
    }
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
    // Ưu tiên URL đang kích hoạt và Đám Mây Azure (Internet 24/7), sau đó chuyển tiếp cáp USB và LAN
    final endpoints = {_currentServerUrl, defaultInternetUrl, defaultUsbUrl, defaultWifiUrl}.toList();
    for (final url in endpoints) {
      try {
        final res = await action(url);
        if (_currentServerUrl != url) {
          _currentServerUrl = url;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('caregiver_server_url', url);
        }
        if (res.statusCode == 401 && !url.contains('/api/v1/auth/login')) {
          await logout();
          sessionExpiredNotifier.value = true;
        }
        return res;
      } catch (_) {
        // Tiếp tục thử kênh dự phòng tiếp theo
      }
    }
    throw Exception('Không thể kết nối đến máy chủ CareAI qua Đám Mây Azure hoặc Cáp USB.');
  }

  // 1. Kiểm tra sức khỏe máy chủ (/health)
  Future<bool> checkHealth([String? targetUrl]) async {
    if (targetUrl != null) {
      try {
        final response = await http
            .get(Uri.parse('$targetUrl/health'))
            .timeout(const Duration(seconds: 3));
        return response.statusCode == 200 && response.body.contains('Healthy');
      } catch (_) {
        return false;
      }
    }

    // Ưu tiên URL đang kích hoạt và Đám Mây Azure trước, sau đó tới Cáp USB và Wi-Fi LAN
    final candidates = {_currentServerUrl, defaultInternetUrl, defaultUsbUrl, defaultWifiUrl};
    for (final url in candidates) {
      try {
        final timeoutMs = url.contains('127.0.0.1') ? 800 : 3000;
        final response = await http
            .get(Uri.parse('$url/health'))
            .timeout(Duration(milliseconds: timeoutMs));
        if (response.statusCode == 200 && response.body.contains('Healthy')) {
          _currentServerUrl = url;
          return true;
        }
      } catch (_) {}
    }

    return false;
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
    } else if (response.statusCode == 401) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err.isNotEmpty ? err : 'Email hoặc mật khẩu không chính xác.');
    } else if (response.statusCode == 423) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err.isNotEmpty ? err : 'Tài khoản đã bị tạm khóa 15 phút do nhập sai mật khẩu quá 5 lần.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 11. Quên mật khẩu - Gửi mã OTP qua Email (NV 3.1)
  Future<void> forgotPassword(String email) async {
    final body = jsonEncode({
      'email': email.trim().toLowerCase(),
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/forgot-password'),
          headers: _buildHeaders(null),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 12. Xác nhận OTP & Đổi mật khẩu mới (NV 3.1)
  Future<void> resetPassword({
    required String email,
    required String otpCode,
    required String newPassword,
  }) async {
    final body = jsonEncode({
      'email': email.trim().toLowerCase(),
      'otpCode': otpCode.trim(),
      'newPassword': newPassword,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/auth/reset-password'),
          headers: _buildHeaders(null),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 13. Chỉnh sửa hồ sơ Người cao tuổi (NV 3.2 - Primary only)
  Future<ElderItem> updateElder(
    String elderId, {
    String? fullName,
    DateTime? dateOfBirth,
    String? medicalNotes,
    String? emergencyContact,
  }) async {
    final token = await getToken();
    final body = jsonEncode({
      'fullName': fullName?.trim(),
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'medicalNotes': medicalNotes?.trim(),
      'emergencyContact': emergencyContact?.trim(),
    });

    final response = await _executeWithFailover((baseUrl) => http
        .put(
          Uri.parse('$baseUrl/api/v1/caregivers/elders/$elderId'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return ElderItem.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 403) {
      throw Exception('Chỉ người bảo hộ chính (Primary) mới có quyền chỉnh sửa hồ sơ.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 14. Tạo mã mời gia đình 6 ký tự (NV 3.3 - Primary only, TTL 24h)
  Future<FamilyInvitationResponse> createFamilyInvitation(String elderId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/elders/$elderId/invitations'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 201) {
      return FamilyInvitationResponse.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 403) {
      throw Exception('Chỉ người bảo hộ chính (Primary) mới có quyền tạo mã mời gia đình.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 15. Chấp nhận mã mời gia đình 6 ký tự (NV 3.3)
  Future<AcceptInvitationResponse> acceptFamilyInvitation(String invitationCode) async {
    final token = await getToken();
    final body = jsonEncode({
      'invitationCode': invitationCode.trim().toUpperCase(),
    });

    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/invitations/accept'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return AcceptInvitationResponse.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 409) {
      throw Exception('Bạn đã là thành viên trong nhóm chăm sóc của người cao tuổi này.');
    } else if (response.statusCode == 400 || response.statusCode == 404) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err.isNotEmpty ? err : 'Mã mời không chính xác hoặc đã hết hạn (24 giờ).');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 16. Lấy danh sách thành viên nhóm chăm sóc (NV 3.3)
  Future<List<FamilyMember>> getFamilyMembers(String elderId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/elders/$elderId/members'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => FamilyMember.fromJson(e as Map<String, dynamic>)).toList();
    } else if (response.statusCode == 403) {
      throw Exception('Bạn không có quyền xem nhóm gia đình này.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 17. Thu hồi quyền thành viên khỏi nhóm gia đình (NV 3.3 - Primary only)
  Future<void> revokeFamilyMember(String elderId, String targetCaregiverId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .delete(
          Uri.parse('$baseUrl/api/v1/elders/$elderId/members/$targetCaregiverId'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return;
    } else if (response.statusCode == 403) {
      throw Exception('Chỉ người bảo hộ chính (Primary) mới có quyền thu hồi thành viên.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 18. Hủy ghép nối thiết bị an toàn (NV 3.5 - Primary only, Wipe Credentials)
  Future<UnpairDeviceResponse> unpairDevice(String deviceId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .post(
          Uri.parse('$baseUrl/api/v1/devices/$deviceId/unpair'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return UnpairDeviceResponse.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 403) {
      throw Exception('Chỉ người bảo hộ chính (Primary) mới có quyền hủy ghép nối thiết bị.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 19. Xóa hồ sơ Người cao tuổi & Ẩn danh hóa PII (NV 3.5 - Primary only, Password cấp 2)
  Future<DeleteElderResponse> deleteElder(String elderId, String password) async {
    final token = await getToken();
    final body = jsonEncode({
      'password': password,
    });

    final response = await _executeWithFailover((baseUrl) => http
        .delete(
          Uri.parse('$baseUrl/api/v1/elders/$elderId'),
          headers: _buildHeaders(token),
          body: body,
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      return DeleteElderResponse.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 400) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err.isNotEmpty ? err : 'Mật khẩu xác nhận cấp 2 không chính xác.');
    } else if (response.statusCode == 403) {
      throw Exception('Chỉ người bảo hộ chính (Primary) mới có quyền xóa hồ sơ người cao tuổi.');
    } else if (response.statusCode == 409) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err.isNotEmpty ? err : 'Không thể xóa hồ sơ khi đang có sự cố cấp cứu chưa giải quyết. Vui lòng đóng sự cố trước.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final items = list.map((e) => ElderItem.fromJson(e as Map<String, dynamic>)).toList();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('caregiver_cached_elder_ids', items.map((e) => e.id).toList());
      } catch (_) {}
      return items;
    } else if (response.statusCode == 401) {
      await logout();
      throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  // 7. Bảng điều khiển Sức khỏe Trực tiếp của Người cao tuổi (UC-10)
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  /// Lấy các mẫu đo sinh hiệu thô gần nhất trong vòng 24 giờ (VitalsController: GET /api/v1/elders/{id}/vitals/recent)
  Future<List<Map<String, dynamic>>> getRecentRawVitals(String elderProfileId) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http
        .get(
          Uri.parse('$baseUrl/api/v1/elders/$elderProfileId/vitals/recent'),
          headers: _buildHeaders(token),
        )
        .timeout(const Duration(seconds: 10)));

    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.cast<Map<String, dynamic>>();
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
    final err = _extractError(response.body, response.statusCode);
    throw Exception(err);
  }

  Future<Uint8List?> getIncidentPhoto(String id) async {
    final token = await getToken();
    final response = await _executeWithFailover((baseUrl) => http.get(
      Uri.parse('$baseUrl/api/v1/incidents/${Uri.encodeComponent(id)}/photo'),
      headers: _buildHeaders(token),
    ).timeout(const Duration(seconds: 8)));
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
    } else {
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
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
      final err = _extractError(response.body, response.statusCode);
      throw Exception(err);
    }
  }

  String _extractError(String responseBody, [int? statusCode]) {
    final trimmed = responseBody.trim();
    if (trimmed.isEmpty) {
      return _defaultMessageForStatus(statusCode);
    }

    // Nếu trả về HTML (ví dụ: màn hình lỗi mặc định của IIS/Azure/Kestrel)
    if (trimmed.startsWith('<') || trimmed.contains('<html') || trimmed.contains('<!DOCTYPE')) {
      final titleMatch = RegExp(r'<title>(.*?)</title>', caseSensitive: false).firstMatch(trimmed);
      final pageTitle = titleMatch?.group(1)?.trim();
      if (pageTitle != null && pageTitle.isNotEmpty && !pageTitle.toLowerCase().contains('error')) {
        return '$pageTitle (Mã lỗi: ${statusCode ?? 500})';
      }
      return _defaultMessageForStatus(statusCode);
    }

    try {
      final data = jsonDecode(trimmed);
      if (data is Map) {
        if (data['error'] != null && data['error'].toString().trim().isNotEmpty) {
          return data['error'].toString().trim();
        }
        if (data['message'] != null && data['message'].toString().trim().isNotEmpty) {
          return data['message'].toString().trim();
        }
        if (data['detail'] != null && data['detail'].toString().trim().isNotEmpty) {
          return data['detail'].toString().trim();
        }
        if (data['title'] != null && data['title'].toString().trim().isNotEmpty) {
          return data['title'].toString().trim();
        }
        // Trường hợp ASP.NET Core Validation Errors: { "errors": { "Email": ["..."] } }
        if (data['errors'] is Map) {
          final errMap = data['errors'] as Map;
          final messages = <String>[];
          for (final entry in errMap.entries) {
            if (entry.value is List) {
              messages.addAll((entry.value as List).map((e) => e.toString()));
            } else if (entry.value != null) {
              messages.add(entry.value.toString());
            }
          }
          if (messages.isNotEmpty) {
            return messages.join(', ');
          }
        }
      }
    } catch (_) {}

    return _defaultMessageForStatus(statusCode, fallbackText: trimmed);
  }

  String _defaultMessageForStatus(int? statusCode, {String? fallbackText}) {
    if (fallbackText != null && fallbackText.isNotEmpty && fallbackText.length < 120 && !fallbackText.startsWith('<')) {
      return fallbackText;
    }
    switch (statusCode) {
      case 400:
        return 'Yêu cầu không hợp lệ hoặc thiếu dữ liệu bắt buộc (Mã 400).';
      case 401:
        return 'Email hoặc mật khẩu không chính xác hoặc phiên đã hết hạn (Mã 401).';
      case 403:
        return 'Bạn không có quyền thực hiện thao tác này (Mã 403).';
      case 404:
        return 'Không tìm thấy thông tin yêu cầu trên hệ thống (Mã 404).';
      case 409:
        return 'Dữ liệu bị xung đột hoặc đã tồn tại trên hệ thống (Mã 409).';
      case 423:
        return 'Tài khoản đã bị tạm khóa 15 phút do nhập sai mật khẩu quá 5 lần.';
      case 500:
        return 'Máy chủ nội bộ hoặc cơ sở dữ liệu gặp sự cố (Mã 500). Vui lòng thử lại sau.';
      case 502:
        return 'Cổng kết nối máy chủ không khả dụng (Bad Gateway 502).';
      case 503:
        return 'Dịch vụ máy chủ hoặc CSDL đang bảo trì/tạm dừng (Service Unavailable 503).';
      case 504:
        return 'Hết thời gian chờ phản hồi từ máy chủ (Gateway Timeout 504).';
      default:
        return statusCode != null
            ? 'Yêu cầu thất bại với mã lỗi HTTP $statusCode.'
            : 'Không thể kết nối đến máy chủ CareAI.';
    }
  }
}

