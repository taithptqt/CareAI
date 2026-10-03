import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class CurrentGpsFix {
  final double latitude;
  final double longitude;
  final DateTime capturedAt;
  final double? accuracyMeters;
  final bool isSimulated;

  const CurrentGpsFix(this.latitude, this.longitude, this.capturedAt,
      {this.accuracyMeters, this.isSimulated = false});

  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

/// Collects evidence without delaying the first emergency request.
class EmergencyEvidenceService {
  EmergencyEvidenceService._();
  static const _sourceChannel = MethodChannel('vn.careai.companion/location_source');
  static CurrentGpsFix? _recentFix;

  static CurrentGpsFix? get recentFix {
    final fix = _recentFix;
    return fix != null &&
            DateTime.now().difference(fix.capturedAt).abs() <
                const Duration(seconds: 15)
        ? fix
        : null;
  }

  static Future<void> requestPermissions() async {
    await Permission.locationWhenInUse.request();
    await Permission.camera.request();
  }

  static Future<CurrentGpsFix?> captureCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      // Some providers may return a cached fix. Reject stale coordinates.
      if (DateTime.now().difference(position.timestamp).abs() >
          const Duration(seconds: 30)) {
        return null;
      }
      bool isEmulator = false;
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          isEmulator = await _sourceChannel.invokeMethod<bool>('isEmulator') ?? false;
        } catch (_) {}
      }
      final fix = CurrentGpsFix(
          position.latitude, position.longitude, position.timestamp.toUtc(),
          accuracyMeters: position.accuracy.isFinite && position.accuracy > 0
              ? position.accuracy : null,
          isSimulated: position.isMocked || isEmulator);
      _recentFix = fix;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('careai_recent_gps', fix.coordinates);
      await prefs.setInt('careai_recent_gps_at', fix.capturedAt.millisecondsSinceEpoch);
      await prefs.setBool('careai_recent_gps_simulated', fix.isSimulated);
      if (fix.accuracyMeters != null) {
        await prefs.setDouble('careai_recent_gps_accuracy', fix.accuracyMeters!);
      }
      return fix;
    } catch (_) {
      return null;
    }
  }

  static Future<void> attachLocationWhenReady(
      String incidentId, Future<CurrentGpsFix?> locationTask,
      {String? initiallySentGps}) async {
    final fix = await locationTask;
    if (fix == null || fix.coordinates == initiallySentGps) return;
    await ApiService.instance.attachIncidentLocation(
        incidentId, fix.coordinates, fix.capturedAt,
        isSimulated: fix.isSimulated, accuracyMeters: fix.accuracyMeters);
  }

  static Future<Uint8List?> capturePhotoIfVisible() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        !await Permission.camera.isGranted) {
      return null;
    }
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;
      final camera = cameras.where((c) => c.lensDirection == CameraLensDirection.back)
          .firstOrNull ?? cameras.first;
      controller = CameraController(camera, ResolutionPreset.low, enableAudio: false);
      await controller.initialize().timeout(const Duration(seconds: 6));
      final photo = await controller.takePicture().timeout(const Duration(seconds: 6));
      final bytes = await photo.readAsBytes();
      return bytes.length <= 1000000 ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  static Future<bool> captureAndUploadPhoto(String incidentId) async {
    final jpeg = await capturePhotoIfVisible();
    if (jpeg == null) return false;
    return ApiService.instance.uploadIncidentPhoto(incidentId, jpeg, DateTime.now().toUtc());
  }
}
