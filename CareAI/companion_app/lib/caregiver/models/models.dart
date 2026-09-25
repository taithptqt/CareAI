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
  final int todaySteps;
  final int stepGoal;
  final String? lastKnownGpsLocation;
  final DateTime? lastSyncedAt;
  final Incident? activeEmergency;

  ElderDashboard({
    required this.elderProfileId,
    required this.fullName,
    required this.age,
    required this.statusBadgeColor,
    required this.deviceStatus,
    this.latestHeartRate,
    this.latestBloodPressure,
    this.latestSpO2,
    required this.todaySteps,
    required this.stepGoal,
    this.lastKnownGpsLocation,
    this.lastSyncedAt,
    this.activeEmergency,
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
      todaySteps: json['todaySteps'] ?? 0,
      stepGoal: json['stepGoal'] ?? 6000,
      lastKnownGpsLocation: json['lastKnownGpsLocation'],
      lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.tryParse(json['lastSyncedAt']) : null,
      activeEmergency: json['activeEmergency'] != null ? Incident.fromJson(json['activeEmergency']) : null,
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
