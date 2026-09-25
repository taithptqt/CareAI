import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/caregiver/models/models.dart';

void main() {
  group('Nhiệm vụ 1.5 - Adaptive Thresholds Models Tests', () {
    test('ThresholdData deserializes correctly from backend API response', () {
      final json = {
        'elderProfileId': 'ELDER_001',
        'restingHeartRateMin': 50.0,
        'restingHeartRateMax': 115.0,
        'updatedAt': '2026-09-25T12:00:00Z',
      };

      final data = ThresholdData.fromJson(json);
      expect(data.elderProfileId, 'ELDER_001');
      expect(data.restingHeartRateMin, 50.0);
      expect(data.restingHeartRateMax, 115.0);
      expect(data.updatedAt, isNotNull);
      expect(data.updatedAt!.year, 2026);
    });

    test('ThresholdRecommendation deserializes P5/P95, drift bounds and rationale', () {
      final json = {
        'elderProfileId': 'ELDER_002',
        'currentMinBpm': 40.0,
        'currentMaxBpm': 120.0,
        'calculatedP5': 52.4,
        'calculatedP95': 96.8,
        'recommendedMinBpm': 43.0,
        'recommendedMaxBpm': 117.0,
        'totalSamplesAnalyzed': 150,
        'analyzedAt': '2026-09-25T12:30:00Z',
        'hasSufficientData': true,
        'clinicalRationale': 'Phân tích 150 mẫu nhịp tim 14 ngày. P5=52.4, P95=96.8 bpm.',
      };

      final rec = ThresholdRecommendation.fromJson(json);
      expect(rec.elderProfileId, 'ELDER_002');
      expect(rec.currentMinBpm, 40.0);
      expect(rec.currentMaxBpm, 120.0);
      expect(rec.calculatedP5, 52.4);
      expect(rec.calculatedP95, 96.8);
      expect(rec.recommendedMinBpm, 43.0);
      expect(rec.recommendedMaxBpm, 117.0);
      expect(rec.totalSamplesAnalyzed, 150);
      expect(rec.hasSufficientData, isTrue);
      expect(rec.clinicalRationale, contains('Phân tích 150 mẫu'));
    });
  });
}
