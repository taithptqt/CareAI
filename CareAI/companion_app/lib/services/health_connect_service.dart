import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/telemetry_sample.dart';
import 'local_offline_store.dart';
import 'sync_service.dart';

/// Dịch vụ thu thập sinh hiệu từ Google Health Connect.
/// Phục vụ Nhiệm vụ 1.1 theo Bản Kế hoạch Triển khai CareAI v111.0
class HealthConnectService {
  static final HealthConnectService instance = HealthConnectService._init();
  HealthConnectService._init();

  static const MethodChannel _channel = MethodChannel('vn.careai.companion/health_connect');

  /// Kiểm tra Google Health Connect có sẵn trên thiết bị hay không
  Future<bool> isHealthConnectAvailable() async {
    try {
      final available = await _channel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } on MissingPluginException {
      debugPrint('[HealthConnect] Plugin chưa đăng ký');
      return false;
    } catch (e) {
      debugPrint('[HealthConnect] Lỗi kiểm tra khả dụng: $e');
      return false;
    }
  }

  /// Kiểm tra quyền đọc dữ liệu sinh hiệu (Heart Rate, Steps, Oxygen Saturation)
  Future<bool> hasPermissions() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermissions');
      return granted ?? false;
    } catch (e) {
      debugPrint('[HealthConnect] Lỗi kiểm tra quyền: $e');
      return false;
    }
  }

  /// Yêu cầu người dùng cấp quyền truy cập Health Connect
  Future<bool> requestPermissions() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestPermissions');
      return granted ?? false;
    } catch (e) {
      debugPrint('[HealthConnect] Lỗi yêu cầu quyền: $e');
      return false;
    }
  }

  /// Thu thập các mẫu sinh hiệu gần nhất từ Google Health Connect
  /// Bao gồm: HeartRateRecord, StepsRecord, OxygenSaturationRecord
  Future<List<TelemetrySample>> readRecentRecords({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final List<TelemetrySample> samples = [];

    final available = await isHealthConnectAvailable();
    final permitted = available && await hasPermissions();

    if (permitted) {
      try {
        final rawData = await _channel.invokeMethod<List<dynamic>>('readRecords', {
          'startTime': startTime.millisecondsSinceEpoch,
          'endTime': endTime.millisecondsSinceEpoch,
        });

        if (rawData != null && rawData.isNotEmpty) {
          for (final item in rawData) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              samples.add(TelemetrySample.fromJson(map));
            }
          }
          debugPrint('[HealthConnect] Đã đọc ${samples.length} mẫu sinh hiệu thực từ Health Connect');
          return samples;
        }
      } catch (e) {
        debugPrint('[HealthConnect] Lỗi đọc bản ghi từ Health Connect: $e');
      }
    }

    // Không tạo chỉ số giả khi chưa có quyền hoặc chưa có mẫu đo.
    return samples;
  }

  /// Hàm gặt hái sinh hiệu chính (Harvesting Pipeline)
  /// Đọc dữ liệu sinh hiệu mới nhất và lưu vào SQLite Spool ở trạng thái Synced = 0
  Future<int> harvestAndSpoolVitals() async {
    final now = DateTime.now().toUtc();
    final lastSync = await LocalOfflineStore.instance.getLastSyncTimestamp();

    // Thu thập từ mốc đồng bộ trước, hoặc mặc định 15 phút gần nhất
    final startTime = lastSync ?? now.subtract(const Duration(minutes: 15));
    final endTime = now;

    if (endTime.difference(startTime).inSeconds < 30) {
      debugPrint('[HealthConnect] Dữ liệu vừa được thu thập gần đây, bỏ qua lượt này');
      return 0;
    }

    final samples = await readRecentRecords(startTime: startTime, endTime: endTime);
    if (samples.isEmpty) return 0;

    // Đưa vào SQLite outbox spool (careai_local_spool.db) với Synced = 0
    await SyncService.instance.enqueueTelemetrySamples(samples);
    debugPrint('[HealthConnect] Đã gặt hái và lưu vào SQLite Spool: ${samples.length} mẫu sinh hiệu');

    return samples.length;
  }
}
