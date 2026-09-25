import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/models/telemetry_sample.dart';

void main() {
  TelemetrySample heartRate(double value) => TelemetrySample(
        metricType: 'HEART_RATE',
        value: value,
        unit: 'bpm',
        timestamp: DateTime.utc(2026, 1, 1),
      );

  test('critical heart rate is routed to urgent transport at both limits', () {
    expect(heartRate(185).isCriticalHeartRate, isTrue);
    expect(heartRate(180).isCriticalHeartRate, isTrue);
    expect(heartRate(35).isCriticalHeartRate, isTrue);
    expect(heartRate(179).isCriticalHeartRate, isFalse);
    expect(heartRate(36).isCriticalHeartRate, isFalse);
    expect(heartRate(double.nan).isCriticalHeartRate, isFalse);
  });
}
