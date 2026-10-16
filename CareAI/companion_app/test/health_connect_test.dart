import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/models/telemetry_sample.dart';
import 'package:careai_companion/models/client_packet.dart';
import 'package:careai_companion/services/health_connect_service.dart';
import 'package:careai_companion/services/fall_service.dart';

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

    test('WatchStatus parses todaySteps correctly from native bridge payload', () {
      final withSteps = WatchStatus.fromMap({
        'isConnected': true,
        'watchName': 'Apple Watch Series 10',
        'isWorn': true,
        'isCharging': false,
        'batteryLevel': 92,
        'todaySteps': 4520,
      });
      expect(withSteps.isConnected, isTrue);
      expect(withSteps.watchName, 'Apple Watch Series 10');
      expect(withSteps.todaySteps, 4520);
      expect(withSteps.isWorn, isTrue);
      expect(withSteps.batteryLevel, 92);

      final withoutSteps = WatchStatus.fromMap({
        'isConnected': true,
        'watchName': 'Apple Watch SE',
      });
      expect(withoutSteps.isConnected, isTrue);
      expect(withoutSteps.todaySteps, isNull);
    });

    test('WatchStatus parses multi-metric vitals (HR, SpO2, BP, Sleep, SupportedMetrics) correctly', () {
      final multiMetric = WatchStatus.fromMap({
        'isConnected': true,
        'watchName': 'Galaxy Watch6',
        'isWorn': true,
        'batteryLevel': 85,
        'todaySteps': 6120,
        'heartRate': 72.0,
        'spo2': 98.0,
        'bpSystolic': 120.0,
        'bpDiastolic': 80.0,
        'sleepMinutes': 450,
        'supportedMetrics': ['HEART_RATE', 'STEPS', 'SPO2', 'BLOOD_PRESSURE', 'SLEEP'],
      });
      expect(multiMetric.isConnected, isTrue);
      expect(multiMetric.watchName, 'Galaxy Watch6');
      expect(multiMetric.todaySteps, 6120);
      expect(multiMetric.heartRate, 72.0);
      expect(multiMetric.spo2, 98.0);
      expect(multiMetric.bpSystolic, 120.0);
      expect(multiMetric.bpDiastolic, 80.0);
      expect(multiMetric.sleepMinutes, 450);
      expect(multiMetric.supportedMetrics, containsAll(['HEART_RATE', 'STEPS', 'SPO2', 'BLOOD_PRESSURE', 'SLEEP']));

      // Watch không có cảm biến huyết áp / giấc ngủ (null) thì trường tương ứng là null, không gán bừa
      final minimalWatch = WatchStatus.fromMap({
        'isConnected': true,
        'watchName': 'Apple Watch SE',
        'todaySteps': 3000,
        'heartRate': 80.0,
      });
      expect(minimalWatch.bpSystolic, isNull);
      expect(minimalWatch.bpDiastolic, isNull);
      expect(minimalWatch.sleepMinutes, isNull);
      expect(minimalWatch.spo2, isNull);
      expect(minimalWatch.todaySteps, 3000);
      expect(minimalWatch.heartRate, 80.0);
    });
  });
}
