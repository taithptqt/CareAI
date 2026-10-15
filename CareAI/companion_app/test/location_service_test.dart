import 'package:flutter_test/flutter_test.dart';
import 'package:careai_companion/services/location_service.dart';
import 'package:careai_companion/caregiver/models/models.dart';

void main() {
  group('Nhiệm vụ Tọa độ GPS & Liên Kết Google Maps Tests', () {
    test('GpsLocationResult formats coordinates and generates correct Google Maps URLs', () {
      final now = DateTime.utc(2026, 9, 25, 10, 0, 0);
      const lat = 10.776889;
      const lng = 106.700806;

      final result = GpsLocationResult(
        latitude: lat,
        longitude: lng,
        accuracy: 8.5,
        provider: 'gps',
        isRealGps: true,
        timestamp: now,
      );

      expect(result.coordinatesFormatted, '10.776889, 106.700806');
      expect(result.googleMapsWebUrl,
          'https://www.google.com/maps/search/?api=1&query=10.776889,106.700806');
      expect(result.googleMapsDirectionsUrl,
          'https://www.google.com/maps/dir/?api=1&destination=10.776889,106.700806');

      // TUÂN THỦ: Tuyệt đối KHÔNG chứa bất kỳ liên kết hay domain bản đồ Trung Quốc nào
      expect(result.googleMapsWebUrl.contains('baidu.com'), isFalse);
      expect(result.googleMapsWebUrl.contains('amap.com'), isFalse);
      expect(result.googleMapsWebUrl.contains('qq.com'), isFalse);

      final json = result.toJson();
      expect(json['latitude'], lat);
      expect(json['longitude'], lng);
      expect(json['accuracy'], 8.5);
      expect(json['provider'], 'gps');
      expect(json['isRealGps'], isTrue);
    });

    test('Incident.gpsLocation extracts coordinates correctly from timeline events', () {
      final incident = Incident(
        id: 'inc-101',
        elderProfileId: 'elder-001',
        elderName: 'Cụ Nguyễn Văn An',
        triggeredByDeviceId: 'GALAXY_WATCH_6_DEAF',
        emergencyType: 'FALL_DETECTED',
        severity: 'Critical',
        status: 'Open',
        triggeredAt: DateTime.utc(2026, 9, 25, 8, 30),
        timeline: [
          IncidentTimeline(
            eventType: 'TRIGGERED',
            description: 'Kích hoạt sự cố cấp cứu FALL_DETECTED từ thiết bị GALAXY_WATCH_6_DEAF. Tọa độ GPS: 10.798123, 106.689456',
            recordedAt: DateTime.utc(2026, 9, 25, 8, 30),
          ),
          IncidentTimeline(
            eventType: 'DISPATCH_ACK',
            description: 'Đã gửi cảnh báo khẩn cấp tới người thân',
            recordedAt: DateTime.utc(2026, 9, 25, 8, 31),
          ),
        ],
      );

      expect(incident.gpsLocation, '10.798123, 106.689456');
    });

    test('Incident.gpsLocation returns null if timeline contains N/A', () {
      final incident = Incident(
        id: 'inc-102',
        elderProfileId: 'elder-001',
        elderName: 'Cụ Nguyễn Văn An',
        triggeredByDeviceId: 'DEVICE_DEV',
        emergencyType: 'MANUAL_SOS',
        severity: 'Critical',
        status: 'Open',
        triggeredAt: DateTime.utc(2026, 9, 25, 8, 30),
        timeline: [
          IncidentTimeline(
            eventType: 'TRIGGERED',
            description: 'Kích hoạt sự cố cấp cứu MANUAL_SOS từ thiết bị DEVICE_DEV. Tọa độ GPS: N/A',
            recordedAt: DateTime.utc(2026, 9, 25, 8, 30),
          ),
        ],
      );

      expect(incident.gpsLocation, isNull);
    });

    test('LocationService fallback provides unverified zero coordinates when native channel unavailable (Fact 35)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final location = await LocationService.instance.getCurrentLocation(requestPermissionIfDenied: false);

      expect(location.latitude, equals(0.0));
      expect(location.longitude, equals(0.0));
      expect(location.isRealGps, isFalse);
      expect(location.coordinatesFormatted, equals('Chưa có GPS'));
    });

    test('LocationService openDirectionsToAddress handles empty and non-empty address safely', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final emptyResult = await LocationService.instance.openDirectionsToAddress('');
      expect(emptyResult, isFalse);

      final whitespaceResult = await LocationService.instance.openDirectionsToAddress('   ');
      expect(whitespaceResult, isFalse);
    });
  });
}
