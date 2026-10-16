import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:careai_companion/caregiver/models/models.dart';
import 'package:careai_companion/services/voice_guidance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gói B: SleepSummaryData & ThresholdData Circadian Tests', () {
    test('SleepSummaryData correctly parses from JSON and computes formatted strings', () {
      final json = {
        'elderProfileId': 'elder-test-123',
        'date': '2026-09-25T00:00:00.000Z',
        'totalSleepMinutes': 435, // 7h 15m
        'sleepStartTime': '2026-09-24T22:15:00.000Z',
        'sleepEndTime': '2026-09-25T05:30:00.000Z',
        'deepSleepMinutes': 120, // 2h 0m
        'lightSleepMinutes': 315, // 5h 15m
        'wakeCount': 1,
        'sleepQuality': 'Tốt (Đạt chuẩn y tế)',
        'statusColor': 'GREEN',
      };

      final data = SleepSummaryData.fromJson(json);

      expect(data.elderProfileId, equals('elder-test-123'));
      expect(data.totalSleepMinutes, equals(435));
      expect(data.formattedDuration, equals('7h 15p'));
      expect(data.formattedDeepSleep, equals('2h 0p'));
      expect(data.formattedLightSleep, equals('5h 15p'));
      expect(data.wakeCount, equals(1));
      expect(data.sleepQuality, equals('Tốt (Đạt chuẩn y tế)'));
      expect(data.statusColor, equals('GREEN'));
    });

    test('SleepSummaryData parses advanced sleep stages, night vitals, and detects apnea warning', () {
      final json = {
        'elderProfileId': 'elder-adv-sleep',
        'date': '2026-10-16T00:00:00.000Z',
        'totalSleepMinutes': 460,
        'deepSleepMinutes': 85,
        'lightSleepMinutes': 250,
        'wakeCount': 4,
        'sleepQuality': 'Nguy cơ ngưng thở / Thiếu oxy ban đêm',
        'statusColor': 'RED',
        'remSleepMinutes': 85,
        'awakeMinutes': 40,
        'minSleepingHeartRate': 52.0,
        'avgSleepingHeartRate': 60.5,
        'minNightSpo2': 84.0,
        'nightSpo2DipsCount': 6,
        'breathingDisturbances': 'ELEVATED',
      };

      final data = SleepSummaryData.fromJson(json);

      expect(data.remSleepMinutes, equals(85));
      expect(data.formattedRemSleep, equals('1h 25p'));
      expect(data.awakeMinutes, equals(40));
      expect(data.formattedAwake, equals('40p'));
      expect(data.hasAdvancedStages, isTrue);
      expect(data.hasApneaWarning, isTrue);
      expect(data.minNightSpo2, equals(84.0));
      expect(data.breathingDisturbances, equals('ELEVATED'));
    });

    test('ThresholdData correctly parses circadian night thresholds and sleep window', () {
      final json = {
        'elderProfileId': 'elder-circadian-1',
        'restingHeartRateMin': 50.0,
        'restingHeartRateMax': 110.0,
        'updatedAt': '2026-09-25T10:00:00.000Z',
        'nightHeartRateMin': 42.0,
        'nightHeartRateMax': 88.0,
        'sleepWindowStart': '21:30',
        'sleepWindowEnd': '05:45',
        'isCurrentlySleepWindow': true,
      };

      final data = ThresholdData.fromJson(json);

      expect(data.restingHeartRateMin, equals(50.0));
      expect(data.restingHeartRateMax, equals(110.0));
      expect(data.nightHeartRateMin, equals(42.0));
      expect(data.nightHeartRateMax, equals(88.0));
      expect(data.sleepWindowStart, equals('21:30'));
      expect(data.sleepWindowEnd, equals('05:45'));
      expect(data.isCurrentlySleepWindow, isTrue);
    });
  });

  group('Gói C: VoiceGuidanceService Tests (TTS Bridge)', () {
    const channel = MethodChannel('vn.careai.companion/tts_bridge');
    final List<MethodCall> log = [];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
        log.add(methodCall);
        switch (methodCall.method) {
          case 'speak':
            return true;
          case 'stop':
            return true;
          case 'isLanguageAvailable':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('speakFallDetected invokes TTS bridge with calm calming instructions', () async {
      final res = await VoiceGuidanceService.instance.speakFallDetected();
      expect(res, isTrue);
      expect(log.length, equals(1));
      expect(log[0].method, equals('speak'));
      final text = log[0].arguments['text'] as String;
      expect(text, contains('Phát hiện có thể bạn vừa bị ngã'));
      expect(text, contains('Tôi Ổn'));
    });

    test('speakCaregiverAcknowledged invokes TTS bridge with caregiver name', () async {
      final res = await VoiceGuidanceService.instance.speakCaregiverAcknowledged('Bác sĩ Tuấn');
      expect(res, isTrue);
      expect(log.length, equals(1));
      expect(log[0].method, equals('speak'));
      final text = log[0].arguments['text'] as String;
      expect(text, contains('Bác sĩ Tuấn đã nhận được tin báo'));
      expect(text, contains('giữ bình tĩnh'));
    });

    test('speakTachycardiaAlert invokes TTS bridge with BPM value', () async {
      final res = await VoiceGuidanceService.instance.speakTachycardiaAlert(145);
      expect(res, isTrue);
      expect(log.length, equals(1));
      expect(log[0].method, equals('speak'));
      final text = log[0].arguments['text'] as String;
      expect(text, contains('145 nhịp một phút'));
      expect(text, contains('nghỉ ngơi'));
    });

    test('speakBradycardiaAlert invokes TTS bridge with BPM value', () async {
      final res = await VoiceGuidanceService.instance.speakBradycardiaAlert(38);
      expect(res, isTrue);
      expect(log.length, equals(1));
      expect(log[0].method, equals('speak'));
      final text = log[0].arguments['text'] as String;
      expect(text, contains('38 nhịp một phút'));
      expect(text, contains('chậm'));
    });

    test('stop invokes stop on native TTS bridge', () async {
      final res = await VoiceGuidanceService.instance.stop();
      expect(res, isTrue);
      expect(log.length, equals(1));
      expect(log[0].method, equals('stop'));
    });
  });
}
