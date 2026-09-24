import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../models/incident_dto.dart';
import '../models/telemetry_sample.dart';
import 'api_service.dart';
import 'local_offline_store.dart';

class SyncResult {
  final int syncedCount;
  final int failedCount;
  final int remainingPending;

  SyncResult({
    required this.syncedCount,
    required this.failedCount,
    required this.remainingPending,
  });
}

class SyncService {
  static final SyncService instance = SyncService._init();
  SyncService._init();

  Timer? _periodicTimer;
  bool _isSyncing = false;

  /// Bắt đầu chu kỳ đồng bộ tự động mỗi 15 phút (UC-03 Offline-to-Online Batch Sync)
  void startPeriodicSync({Duration interval = const Duration(minutes: 15)}) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) => syncOfflineSpool());
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// Đồng bộ toàn bộ hàng đợi ngoại tuyến từ SQLite Spool lên Backend API
  Future<SyncResult> syncOfflineSpool() async {
    if (_isSyncing) {
      final pending = await LocalOfflineStore.instance.getPendingCount();
      return SyncResult(syncedCount: 0, failedCount: 0, remainingPending: pending);
    }

    final isPaired = await ApiService.instance.isPaired();
    if (!isPaired) {
      final pending = await LocalOfflineStore.instance.getPendingCount();
      return SyncResult(syncedCount: 0, failedCount: 0, remainingPending: pending);
    }

    _isSyncing = true;
    int syncedCount = 0;
    int failedCount = 0;

    try {
      final pendingPackets = await LocalOfflineStore.instance.getPendingPackets(limit: 50);

      for (final packet in pendingPackets) {
        try {
          if (packet.packetType == 'SOS_ALERT' || packet.packetType == 'FALL_ALERT') {
            final json = jsonDecode(packet.payload) as Map<String, dynamic>;
            final request = SosPacketRequest.fromJson(json);
            final success = await ApiService.instance.sendFastLaneSos(request);

            if (success) {
              await LocalOfflineStore.instance.markPacketSynced(packet.packetId);
              syncedCount++;
            } else {
              await LocalOfflineStore.instance.markPacketFailed(packet.packetId);
              failedCount++;
            }
          } else if (packet.packetType == 'TELEMETRY_BATCH') {
            final jsonList = jsonDecode(packet.payload) as List<dynamic>;
            final samples = jsonList
                .map((s) => TelemetrySample.fromJson(s as Map<String, dynamic>))
                .toList();

            final success = await ApiService.instance.sendBatchTelemetry(packet.packetId, samples);

            if (success) {
              await LocalOfflineStore.instance.markPacketSynced(packet.packetId);
              syncedCount++;

              // Cập nhật High-Water Mark timestamp
              if (samples.isNotEmpty) {
                samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
                await LocalOfflineStore.instance.setLastSyncTimestamp(samples.last.timestamp);
              }
            } else {
              await LocalOfflineStore.instance.markPacketFailed(packet.packetId);
              failedCount++;
            }
          }
        } catch (_) {
          await LocalOfflineStore.instance.markPacketFailed(packet.packetId);
          failedCount++;
        }
      }

      // Dọn dẹp bản ghi cũ hơn 7 ngày (không chạy VACUUM)
      await LocalOfflineStore.instance.pruneOldSyncedPackets(retentionDays: 7);
    } finally {
      _isSyncing = false;
    }

    final remainingPending = await LocalOfflineStore.instance.getPendingCount();
    return SyncResult(
      syncedCount: syncedCount,
      failedCount: failedCount,
      remainingPending: remainingPending,
    );
  }

  /// Ghi nhận và lưu gói viễn trắc sinh hiệu vào hàng đợi SQLite Outbox
  Future<void> enqueueTelemetrySamples(List<TelemetrySample> samples) async {
    if (samples.isEmpty) return;
    final batchId = 'BATCH_${const Uuid().v4().substring(0, 8)}';
    final payloadJson = jsonEncode(samples.map((s) => s.toJson()).toList());

    await LocalOfflineStore.instance.enqueuePacket(
      packetId: batchId,
      packetType: 'TELEMETRY_BATCH',
      payload: payloadJson,
    );
  }
}
