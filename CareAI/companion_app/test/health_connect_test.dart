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

    test('HealthConnectService fallback generates physiological vitals within safe medical bounds', () async {
      final service = HealthConnectService.instance;
      final startTime = DateTime.now().toUtc().subtract(const Duration(minutes: 15));
      final endTime = DateTime.now().toUtc();

      final samples = await service.readRecentRecords(
        startTime: startTime,
        endTime: endTime,
      );

      expect(samples.isNotEmpty, isTrue, reason: 'Phải sinh ít nhất một số mẫu sinh hiệu');

      // Kiểm tra tất cả mẫu nhịp tim phải nằm trong dải sinh lý người già nghỉ ngơi (60-95 BPM)
      final hrSamples = samples.where((s) => s.metricType == 'HEART_RATE').toList();
      expect(hrSamples.isNotEmpty, isTrue);
      for (final hr in hrSamples) {
        expect(hr.value, greaterThanOrEqualTo(60.0));
        expect(hr.value, lessThanOrEqualTo(95.0));
        expect(hr.unit, 'BPM');
      }

      // Kiểm tra mẫu SpO2 nếu có phải từ 95.0% đến 100.0%
      final spo2Samples = samples.where((s) => s.metricType == 'SPO2').toList();
      for (final spo2 in spo2Samples) {
        expect(spo2.value, greaterThanOrEqualTo(95.0));
        expect(spo2.value, lessThanOrEqualTo(100.0));
        expect(spo2.unit, '%');
      }

      // Kiểm tra mẫu bước chân nếu có phải >= 0
      final stepsSamples = samples.where((s) => s.metricType == 'STEPS').toList();
      for (final step in stepsSamples) {
        expect(step.value, greaterThanOrEqualTo(0.0));
        expect(step.unit, 'STEPS');
      }
    });
  });
}
