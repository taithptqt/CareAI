class CaregiverProfile {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String email;

  CaregiverProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
  });

  factory CaregiverProfile.fromJson(Map<String, dynamic> json) {
    return CaregiverProfile(
      id: json['caregiverId'] ?? json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      email: json['email'] ?? '',
    );
  }
}

class AuthResponse {
  final String token;
  final String caregiverId;
  final String fullName;
  final String email;

  AuthResponse({
    required this.token,
    required this.caregiverId,
    required this.fullName,
    required this.email,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] ?? '',
      caregiverId: json['caregiverId'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
    );
  }
}

class ElderItem {
  final String id;
  final String fullName;
  final DateTime dateOfBirth;
  final String? medicalNotes;
  final String? emergencyContact;
  final String? homeAddress;
  final double? homeLatitude;
  final double? homeLongitude;
  final String? pairingPin;
  final DateTime? pinExpiresAt;
  final int deviceCount;
  final String deviceStatus;

  ElderItem({
    required this.id,
    required this.fullName,
    required this.dateOfBirth,
    this.medicalNotes,
    this.emergencyContact,
    this.homeAddress,
    this.homeLatitude,
    this.homeLongitude,
    this.pairingPin,
    this.pinExpiresAt,
    required this.deviceCount,
    required this.deviceStatus,
  });

  int get age {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month || (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  bool get isPinActive {
    if (pairingPin == null || pinExpiresAt == null) return false;
    return DateTime.now().toUtc().isBefore(pinExpiresAt!.toUtc());
  }

  factory ElderItem.fromJson(Map<String, dynamic> json) {
    return ElderItem(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      dateOfBirth: DateTime.tryParse(json['dateOfBirth'] ?? '') ?? DateTime(1950, 1, 1),
      medicalNotes: json['medicalNotes'],
      emergencyContact: json['emergencyContact'],
      homeAddress: json['homeAddress'] as String?,
      homeLatitude: (json['homeLatitude'] as num?)?.toDouble(),
      homeLongitude: (json['homeLongitude'] as num?)?.toDouble(),
      pairingPin: json['pairingPin'],
      pinExpiresAt: json['pinExpiresAt'] != null ? DateTime.tryParse(json['pinExpiresAt']) : null,
      deviceCount: json['deviceCount'] ?? 0,
      deviceStatus: json['deviceStatus'] ?? 'OFFLINE',
    );
  }
}

class VitalSign {
  final String metricType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final String statusColor;

  VitalSign({
    required this.metricType,
    required this.value,
    required this.unit,
    required this.timestamp,
    required this.statusColor,
  });

  factory VitalSign.fromJson(Map<String, dynamic> json) {
    return VitalSign(
      metricType: json['metricType'] ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      statusColor: json['statusColor'] ?? 'GREEN',
    );
  }
}

class IncidentTimeline {
  final String eventType;
  final String description;
  final DateTime recordedAt;

  IncidentTimeline({
    required this.eventType,
    required this.description,
    required this.recordedAt,
  });

  factory IncidentTimeline.fromJson(Map<String, dynamic> json) {
    return IncidentTimeline(
      eventType: json['eventType'] ?? '',
      description: json['description'] ?? '',
      recordedAt: DateTime.tryParse(json['recordedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class IncidentSnapshot {
  final double? heartRateBpm;
  final double? spO2Percent;
  final double? bpSystolic;
  final double? bpDiastolic;
  final DateTime? vitalsMeasuredAt;
  final String? gpsLocation;
  final String? currentGpsLocation;
  final DateTime? currentGpsMeasuredAt;
  final bool? currentGpsIsSimulated;
  final double? currentGpsAccuracyMeters;
  final String? homeAddress;

  IncidentSnapshot.fromJson(Map<String, dynamic> json)
      : heartRateBpm = (json['heartRateBpm'] as num?)?.toDouble(),
        spO2Percent = (json['spO2Percent'] as num?)?.toDouble(),
        bpSystolic = (json['bpSystolic'] as num?)?.toDouble(),
        bpDiastolic = (json['bpDiastolic'] as num?)?.toDouble(),
        vitalsMeasuredAt = DateTime.tryParse(json['vitalsMeasuredAt']?.toString() ?? ''),
        gpsLocation = json['gpsLocation'] as String?,
        currentGpsLocation = json['currentGpsLocation'] as String?,
        currentGpsMeasuredAt = DateTime.tryParse(json['currentGpsMeasuredAt']?.toString() ?? ''),
        currentGpsIsSimulated = json['currentGpsIsSimulated'] as bool?,
        currentGpsAccuracyMeters = (json['currentGpsAccuracyMeters'] as num?)?.toDouble(),
        homeAddress = json['homeAddress'] as String?;
}

class IncidentAlertState {
  final int cycleNumber;
  final DateTime? deadlineAt;

  IncidentAlertState.fromJson(Map<String, dynamic> json)
      : cycleNumber = (json['cycleNumber'] as num?)?.toInt() ?? 0,
        deadlineAt = DateTime.tryParse(json['deadlineAt']?.toString() ?? '');
}

class Incident {
  final String id;
  final String elderProfileId;
  final String elderName;
  final String triggeredByDeviceId;
  final String emergencyType;
  final String severity;
  final String status;
  final DateTime triggeredAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedByCaregiverId;
  final DateTime? resolvedAt;
  final String? resolvedByCaregiverId;
  final String? resolutionNotes;
  final String? rowVersion;
  final IncidentSnapshot? snapshot;
  final IncidentAlertState? alertState;
  final IncidentHeartRateWindow? heartRateSeries;
  final List<IncidentTimeline> timeline;

  Incident({
    required this.id,
    required this.elderProfileId,
    required this.elderName,
    required this.triggeredByDeviceId,
    required this.emergencyType,
    required this.severity,
    required this.status,
    required this.triggeredAt,
    this.acknowledgedAt,
    this.acknowledgedByCaregiverId,
    this.resolvedAt,
    this.resolvedByCaregiverId,
    this.resolutionNotes,
    this.rowVersion,
    this.snapshot,
    this.alertState,
    this.heartRateSeries,
    required this.timeline,
  });

  bool get isOpen => status == 'Open';
  bool get isAcknowledged => status == 'Acknowledged';
  bool get isResolved => status == 'Resolved';

  /// Trích xuất tọa độ GPS từ chuỗi sự kiện timeline (nếu có)
  String? get gpsLocation {
    for (final event in timeline) {
      if (event.description.contains('Tọa độ GPS:') &&
          !event.description.contains('N/A')) {
        final marker = 'Tọa độ GPS:';
        final idx = event.description.indexOf(marker);
        if (idx >= 0) {
          final extracted = event.description.substring(idx + marker.length).trim();
          if (extracted.isNotEmpty) return extracted;
        }
      }
      if (event.description.contains('Vị trí GPS:') &&
          !event.description.contains('N/A')) {
        final marker = 'Vị trí GPS:';
        final idx = event.description.indexOf(marker);
        if (idx >= 0) {
          final extracted = event.description.substring(idx + marker.length).trim();
          if (extracted.isNotEmpty) return extracted;
        }
      }
    }
    return null;
  }

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] ?? '',
      elderProfileId: json['elderProfileId'] ?? '',
      elderName: json['elderName'] ?? 'Người cao tuổi',
      triggeredByDeviceId: json['triggeredByDeviceId'] ?? '',
      emergencyType: json['emergencyType'] ?? 'MANUAL_SOS',
      severity: json['severity'] ?? 'Critical',
      status: json['status'] ?? 'Open',
      triggeredAt: DateTime.tryParse(json['triggeredAt'] ?? '') ?? DateTime.now(),
      acknowledgedAt: json['acknowledgedAt'] != null ? DateTime.tryParse(json['acknowledgedAt']) : null,
      acknowledgedByCaregiverId: json['acknowledgedByCaregiverId'],
      resolvedAt: json['resolvedAt'] != null ? DateTime.tryParse(json['resolvedAt']) : null,
      resolvedByCaregiverId: json['resolvedByCaregiverId'],
      resolutionNotes: json['resolutionNotes'],
      rowVersion: json['rowVersion'] as String?,
      snapshot: json['snapshot'] is Map<String, dynamic>
          ? IncidentSnapshot.fromJson(json['snapshot'] as Map<String, dynamic>) : null,
      alertState: json['alertState'] is Map<String, dynamic>
          ? IncidentAlertState.fromJson(json['alertState'] as Map<String, dynamic>) : null,
      heartRateSeries: json['heartRateSeries'] is Map<String, dynamic>
          ? IncidentHeartRateWindow.fromJson(json['heartRateSeries'] as Map<String, dynamic>) : null,
      timeline: (json['timeline'] as List<dynamic>?)
              ?.map((e) => IncidentTimeline.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ElderDashboard {
  final String elderProfileId;
  final String fullName;
  final int age;
  final String statusBadgeColor;
  final String deviceStatus;
  final VitalSign? latestHeartRate;
  final VitalSign? latestBloodPressure;
  final VitalSign? latestSpO2;
  final VitalSign? demoHeartRate;
  final VitalSign? demoSpO2;
  final int todaySteps;
  final int stepGoal;
  final String? lastKnownGpsLocation;
  final DateTime? lastSyncedAt;
  final Incident? activeEmergency;
  final String? watchModel;

  ElderDashboard({
    required this.elderProfileId,
    required this.fullName,
    required this.age,
    required this.statusBadgeColor,
    required this.deviceStatus,
    this.latestHeartRate,
    this.latestBloodPressure,
    this.latestSpO2,
    this.demoHeartRate,
    this.demoSpO2,
    required this.todaySteps,
    required this.stepGoal,
    this.lastKnownGpsLocation,
    this.lastSyncedAt,
    this.activeEmergency,
    this.watchModel,
  });

  factory ElderDashboard.fromJson(Map<String, dynamic> json) {
    return ElderDashboard(
      elderProfileId: json['elderProfileId'] ?? '',
      fullName: json['fullName'] ?? '',
      age: json['age'] ?? 0,
      statusBadgeColor: json['statusBadgeColor'] ?? 'GREEN',
      deviceStatus: json['deviceStatus'] ?? 'OFFLINE',
      latestHeartRate: json['latestHeartRate'] != null ? VitalSign.fromJson(json['latestHeartRate']) : null,
      latestBloodPressure: json['latestBloodPressure'] != null ? VitalSign.fromJson(json['latestBloodPressure']) : null,
      latestSpO2: json['latestSpO2'] != null ? VitalSign.fromJson(json['latestSpO2']) : null,
      demoHeartRate: json['demoHeartRate'] != null ? VitalSign.fromJson(json['demoHeartRate']) : null,
      demoSpO2: json['demoSpO2'] != null ? VitalSign.fromJson(json['demoSpO2']) : null,
      todaySteps: json['todaySteps'] ?? 0,
      stepGoal: json['stepGoal'] ?? 6000,
      lastKnownGpsLocation: json['lastKnownGpsLocation'],
      lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.tryParse(json['lastSyncedAt']) : null,
      activeEmergency: json['activeEmergency'] != null ? Incident.fromJson(json['activeEmergency']) : null,
      watchModel: json['watchModel'] as String?,
    );
  }
}

class HeartRatePoint {
  final DateTime timestamp;
  final double value;

  HeartRatePoint({required this.timestamp, required this.value});

  factory HeartRatePoint.fromJson(Map<String, dynamic> json) {
    return HeartRatePoint(
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class HeartRate24hData {
  final List<HeartRatePoint> points;
  final double minHeartRate;
  final double maxHeartRate;
  final double avgHeartRate;
  final double latestHeartRate;

  HeartRate24hData({
    required this.points,
    required this.minHeartRate,
    required this.maxHeartRate,
    required this.avgHeartRate,
    required this.latestHeartRate,
  });

  factory HeartRate24hData.fromJson(Map<String, dynamic> json) {
    return HeartRate24hData(
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => HeartRatePoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      minHeartRate: (json['minHeartRate'] as num?)?.toDouble() ?? 0.0,
      maxHeartRate: (json['maxHeartRate'] as num?)?.toDouble() ?? 0.0,
      avgHeartRate: (json['avgHeartRate'] as num?)?.toDouble() ?? 0.0,
      latestHeartRate: (json['latestHeartRate'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class ThresholdData {
  final String elderProfileId;
  final double restingHeartRateMin;
  final double restingHeartRateMax;
  final DateTime? updatedAt;
  final double nightHeartRateMin;
  final double nightHeartRateMax;
  final String sleepWindowStart;
  final String sleepWindowEnd;
  final bool isCurrentlySleepWindow;

  ThresholdData({
    required this.elderProfileId,
    required this.restingHeartRateMin,
    required this.restingHeartRateMax,
    this.updatedAt,
    this.nightHeartRateMin = 40.0,
    this.nightHeartRateMax = 90.0,
    this.sleepWindowStart = "22:00",
    this.sleepWindowEnd = "06:00",
    this.isCurrentlySleepWindow = false,
  });

  factory ThresholdData.fromJson(Map<String, dynamic> json) {
    return ThresholdData(
      elderProfileId: json['elderProfileId'] ?? '',
      restingHeartRateMin: (json['restingHeartRateMin'] as num?)?.toDouble() ?? 40.0,
      restingHeartRateMax: (json['restingHeartRateMax'] as num?)?.toDouble() ?? 120.0,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
      nightHeartRateMin: (json['nightHeartRateMin'] as num?)?.toDouble() ?? 40.0,
      nightHeartRateMax: (json['nightHeartRateMax'] as num?)?.toDouble() ?? 90.0,
      sleepWindowStart: json['sleepWindowStart'] ?? '22:00',
      sleepWindowEnd: json['sleepWindowEnd'] ?? '06:00',
      isCurrentlySleepWindow: json['isCurrentlySleepWindow'] ?? false,
    );
  }
}

class SleepSummaryData {
  final String elderProfileId;
  final DateTime date;
  final int totalSleepMinutes;
  final DateTime? sleepStartTime;
  final DateTime? sleepEndTime;
  final int deepSleepMinutes;
  final int lightSleepMinutes;
  final int wakeCount;
  final String sleepQuality;
  final String statusColor;

  SleepSummaryData({
    required this.elderProfileId,
    required this.date,
    required this.totalSleepMinutes,
    this.sleepStartTime,
    this.sleepEndTime,
    required this.deepSleepMinutes,
    required this.lightSleepMinutes,
    required this.wakeCount,
    required this.sleepQuality,
    required this.statusColor,
  });

  String get formattedDuration {
    final hours = totalSleepMinutes ~/ 60;
    final mins = totalSleepMinutes % 60;
    return '${hours}h ${mins}p';
  }

  String get formattedDeepSleep {
    final hours = deepSleepMinutes ~/ 60;
    final mins = deepSleepMinutes % 60;
    return '${hours}h ${mins}p';
  }

  String get formattedLightSleep {
    final hours = lightSleepMinutes ~/ 60;
    final mins = lightSleepMinutes % 60;
    return '${hours}h ${mins}p';
  }

  factory SleepSummaryData.fromJson(Map<String, dynamic> json) {
    return SleepSummaryData(
      elderProfileId: json['elderProfileId'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      totalSleepMinutes: json['totalSleepMinutes'] ?? 0,
      sleepStartTime: json['sleepStartTime'] != null ? DateTime.tryParse(json['sleepStartTime']) : null,
      sleepEndTime: json['sleepEndTime'] != null ? DateTime.tryParse(json['sleepEndTime']) : null,
      deepSleepMinutes: json['deepSleepMinutes'] ?? 0,
      lightSleepMinutes: json['lightSleepMinutes'] ?? 0,
      wakeCount: json['wakeCount'] ?? 0,
      sleepQuality: json['sleepQuality'] ?? 'Bình thường',
      statusColor: json['statusColor'] ?? 'GREEN',
    );
  }
}

class ThresholdRecommendation {
  final String elderProfileId;
  final double currentMinBpm;
  final double currentMaxBpm;
  final double calculatedP5;
  final double calculatedP95;
  final double recommendedMinBpm;
  final double recommendedMaxBpm;
  final int totalSamplesAnalyzed;
  final DateTime analyzedAt;
  final bool hasSufficientData;
  final String clinicalRationale;

  ThresholdRecommendation({
    required this.elderProfileId,
    required this.currentMinBpm,
    required this.currentMaxBpm,
    required this.calculatedP5,
    required this.calculatedP95,
    required this.recommendedMinBpm,
    required this.recommendedMaxBpm,
    required this.totalSamplesAnalyzed,
    required this.analyzedAt,
    required this.hasSufficientData,
    required this.clinicalRationale,
  });

  factory ThresholdRecommendation.fromJson(Map<String, dynamic> json) {
    return ThresholdRecommendation(
      elderProfileId: json['elderProfileId'] ?? '',
      currentMinBpm: (json['currentMinBpm'] as num?)?.toDouble() ?? 40.0,
      currentMaxBpm: (json['currentMaxBpm'] as num?)?.toDouble() ?? 120.0,
      calculatedP5: (json['calculatedP5'] as num?)?.toDouble() ?? 40.0,
      calculatedP95: (json['calculatedP95'] as num?)?.toDouble() ?? 120.0,
      recommendedMinBpm: (json['recommendedMinBpm'] as num?)?.toDouble() ?? 40.0,
      recommendedMaxBpm: (json['recommendedMaxBpm'] as num?)?.toDouble() ?? 120.0,
      totalSamplesAnalyzed: json['totalSamplesAnalyzed'] ?? 0,
      analyzedAt: DateTime.tryParse(json['analyzedAt'] ?? '') ?? DateTime.now(),
      hasSufficientData: json['hasSufficientData'] ?? false,
      clinicalRationale: json['clinicalRationale'] ?? '',
    );
  }
}

class BloodPressurePoint {
  final DateTime timestamp;
  final double systolic;
  final double diastolic;

  BloodPressurePoint({
    required this.timestamp,
    required this.systolic,
    required this.diastolic,
  });

  factory BloodPressurePoint.fromJson(Map<String, dynamic> json) {
    return BloodPressurePoint(
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      systolic: (json['systolic'] as num?)?.toDouble() ?? 120.0,
      diastolic: (json['diastolic'] as num?)?.toDouble() ?? 80.0,
    );
  }
}

class HeartRateSample {
  final double bpm;
  final DateTime timestamp;

  HeartRateSample({
    required this.bpm,
    required this.timestamp,
  });

  factory HeartRateSample.fromJson(Map<String, dynamic> json) {
    return HeartRateSample(
      bpm: (json['bpm'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class BloodPressureHistoryData {
  final List<BloodPressurePoint> points;
  final double latestSystolic;
  final double latestDiastolic;
  final String classification;
  final String statusColor;

  BloodPressureHistoryData({
    required this.points,
    required this.latestSystolic,
    required this.latestDiastolic,
    required this.classification,
    required this.statusColor,
  });

  factory BloodPressureHistoryData.fromJson(Map<String, dynamic> json) {
    return BloodPressureHistoryData(
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => BloodPressurePoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      latestSystolic: (json['latestSystolic'] as num?)?.toDouble() ?? 120.0,
      latestDiastolic: (json['latestDiastolic'] as num?)?.toDouble() ?? 80.0,
      classification: json['classification'] ?? 'Bình thường',
      statusColor: json['statusColor'] ?? 'GREEN',
    );
  }
}

class IncidentHeartRateWindow {
  final DateTime incidentTriggeredAt;
  final DateTime windowStart;
  final DateTime windowEnd;
  final List<HeartRateSample> samples;

  IncidentHeartRateWindow({
    required this.incidentTriggeredAt,
    required this.windowStart,
    required this.windowEnd,
    required this.samples,
  });

  factory IncidentHeartRateWindow.fromJson(Map<String, dynamic> json) {
    return IncidentHeartRateWindow(
      incidentTriggeredAt: DateTime.tryParse(json['incidentTriggeredAt']?.toString() ?? '') ?? DateTime.now(),
      windowStart: DateTime.tryParse(json['windowStart']?.toString() ?? '') ?? DateTime.now(),
      windowEnd: DateTime.tryParse(json['windowEnd']?.toString() ?? '') ?? DateTime.now(),
      samples: (json['samples'] as List<dynamic>?)
              ?.map((e) => HeartRateSample.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class Spo2Point {
  final DateTime timestamp;
  final double value;

  Spo2Point({required this.timestamp, required this.value});

  factory Spo2Point.fromJson(Map<String, dynamic> json) {
    return Spo2Point(
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      value: (json['value'] as num?)?.toDouble() ?? 98.0,
    );
  }
}

class Spo224hData {
  final List<Spo2Point> points;
  final double minSpo2;
  final double maxSpo2;
  final double avgSpo2;
  final double latestSpo2;
  final int dipsBelow95Count;
  final String statusColor;

  Spo224hData({
    required this.points,
    required this.minSpo2,
    required this.maxSpo2,
    required this.avgSpo2,
    required this.latestSpo2,
    required this.dipsBelow95Count,
    required this.statusColor,
  });

  factory Spo224hData.fromJson(Map<String, dynamic> json) {
    return Spo224hData(
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => Spo2Point.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      minSpo2: (json['minSpo2'] as num?)?.toDouble() ?? 95.0,
      maxSpo2: (json['maxSpo2'] as num?)?.toDouble() ?? 99.0,
      avgSpo2: (json['avgSpo2'] as num?)?.toDouble() ?? 97.0,
      latestSpo2: (json['latestSpo2'] as num?)?.toDouble() ?? 98.0,
      dipsBelow95Count: json['dipsBelow95Count'] ?? 0,
      statusColor: json['statusColor'] ?? 'GREEN',
    );
  }
}

class HourlyStepsPoint {
  final int hour;
  final int steps;

  HourlyStepsPoint({required this.hour, required this.steps});

  factory HourlyStepsPoint.fromJson(Map<String, dynamic> json) {
    return HourlyStepsPoint(
      hour: json['hour'] ?? 0,
      steps: json['steps'] ?? 0,
    );
  }
}

class HourlyStepsData {
  final List<HourlyStepsPoint> hourlySteps;
  final int totalStepsToday;
  final int peakHour;
  final int peakSteps;

  HourlyStepsData({
    required this.hourlySteps,
    required this.totalStepsToday,
    required this.peakHour,
    required this.peakSteps,
  });

  factory HourlyStepsData.fromJson(Map<String, dynamic> json) {
    return HourlyStepsData(
      hourlySteps: (json['hourlySteps'] as List<dynamic>?)
              ?.map((p) => HourlyStepsPoint.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      totalStepsToday: json['totalStepsToday'] ?? 0,
      peakHour: json['peakHour'] ?? 0,
      peakSteps: json['peakSteps'] ?? 0,
    );
  }
}

class PagedIncidents {
  final List<Incident> items;
  final int page;
  final int pageSize;
  final int totalCount;
  final int totalPages;
  final bool hasPreviousPage;
  final bool hasNextPage;

  PagedIncidents({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.totalPages,
    required this.hasPreviousPage,
    required this.hasNextPage,
  });

  factory PagedIncidents.fromJson(Map<String, dynamic> json) {
    return PagedIncidents(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Incident.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      hasPreviousPage: json['hasPreviousPage'] as bool? ?? false,
      hasNextPage: json['hasNextPage'] as bool? ?? false,
    );
  }
}

// ===== PHẦN 3: MODELS CHO QUẢN TRỊ NHÓM GIA ĐÌNH & VÒNG ĐỜI THIẾT BỊ =====

class FamilyInvitationResponse {
  final String invitationCode;
  final DateTime expiresAt;

  FamilyInvitationResponse({
    required this.invitationCode,
    required this.expiresAt,
  });

  factory FamilyInvitationResponse.fromJson(Map<String, dynamic> json) {
    return FamilyInvitationResponse(
      invitationCode: json['invitationCode'] ?? '',
      expiresAt: DateTime.tryParse(json['expiresAt'] ?? '') ?? DateTime.now().add(const Duration(hours: 24)),
    );
  }
}

class AcceptInvitationResponse {
  final String elderProfileId;
  final String elderName;
  final String role;

  AcceptInvitationResponse({
    required this.elderProfileId,
    required this.elderName,
    required this.role,
  });

  factory AcceptInvitationResponse.fromJson(Map<String, dynamic> json) {
    return AcceptInvitationResponse(
      elderProfileId: json['elderProfileId'] ?? '',
      elderName: json['elderName'] ?? '',
      role: json['role'] ?? 'Secondary',
    );
  }
}

class FamilyMember {
  final String caregiverId;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String role;
  final bool isActive;
  final DateTime assignedAt;

  FamilyMember({
    required this.caregiverId,
    required this.fullName,
    required this.email,
    required this.phoneNumber,
    required this.role,
    required this.isActive,
    required this.assignedAt,
  });

  bool get isPrimary => role.toUpperCase() == 'PRIMARY';

  factory FamilyMember.fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      caregiverId: json['caregiverId'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      role: json['role'] ?? 'Secondary',
      isActive: json['isActive'] ?? true,
      assignedAt: DateTime.tryParse(json['assignedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class UnpairDeviceResponse {
  final String deviceId;
  final String status;
  final String message;

  UnpairDeviceResponse({
    required this.deviceId,
    required this.status,
    required this.message,
  });

  factory UnpairDeviceResponse.fromJson(Map<String, dynamic> json) {
    return UnpairDeviceResponse(
      deviceId: json['deviceId'] ?? '',
      status: json['status'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

class DeleteElderResponse {
  final String elderProfileId;
  final String status;
  final String message;

  DeleteElderResponse({
    required this.elderProfileId,
    required this.status,
    required this.message,
  });

  factory DeleteElderResponse.fromJson(Map<String, dynamic> json) {
    return DeleteElderResponse(
      elderProfileId: json['elderProfileId'] ?? '',
      status: json['status'] ?? '',
      message: json['message'] ?? '',
    );
  }
}
