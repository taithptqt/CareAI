import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/models/telemetry_sample.dart';
import 'package:careai_companion/models/client_packet.dart';
import 'package:careai_companion/services/health_connect_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nhiệm vụ 1.1 - Telemetry & Health Connect Tests', () {
    test('TelemetrySample serialization and deserialization preserves fields', () {
      final now = DateTime.utc(2026, 9, 25, 10, 30, 0);
      final sample = TelemetrySample(
        metricType: 'HEART_RATE',
        value: 75.5,
        unit: 'BPM',
        timestamp: now,
      );

      final json = sample.toJson();
      expect(json['metricType'], 'HEART_RATE');
      expect(json['value'], 75.5);
      expect(json['unit'], 'BPM');
      expect(json['timestamp'], '2026-09-25T10:30:00.000Z');

      final reconstructed = TelemetrySample.fromJson(json);
      expect(reconstructed.metricType, sample.metricType);
      expect(reconstructed.value, sample.value);
      expect(reconstructed.unit, sample.unit);
      expect(reconstructed.timestamp, sample.timestamp);
    });

    test('ClientPacket serialization and deserialization preserves schema v2', () {
      final packet = ClientPacket(
        id: 1,
        packetId: 'pkt-uuid-12345',
        packetType: 'TELEMETRY_BATCH',
        payload: '{"samples":[]}',
        status: 'PENDING',
        createdAt: 1790320000000,
        syncedAt: null,
        retryCount: 0,
      );

      final map = packet.toMap();
      expect(map['packet_id'], 'pkt-uuid-12345');
      expect(map['packet_type'], 'TELEMETRY_BATCH');
      expect(map['status'], 'PENDING');
      expect(map['retry_count'], 0);

      final reconstructed = ClientPacket.fromMap(map);
      expect(reconstructed.packetId, packet.packetId);
      expect(reconstructed.packetType, packet.packetType);
      expect(reconstructed.payload, packet.payload);
      expect(reconstructed.status, packet.status);
      expect(reconstructed.retryCount, 0);
    });

    test('HealthConnectService returns no invented measurements without a source', () async {
      final service = HealthConnectService.instance;
      final startTime = DateTime.now().toUtc().subtract(const Duration(minutes: 15));
      final endTime = DateTime.now().toUtc();

      final samples = await service.readRecentRecords(
        startTime: startTime,
        endTime: endTime,
      );

      expect(samples, isEmpty);
    });
  });
}
