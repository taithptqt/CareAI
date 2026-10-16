class PairDeviceRequest {
  final String deviceId;
  final String pairingPin;
  final String deviceType;
  final String? firmwareVersion;

  PairDeviceRequest({
    required this.deviceId,
    required this.pairingPin,
    this.deviceType = 'SMARTPHONE_COMPANION',
    this.firmwareVersion = '1.0.0',
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'pairingPin': pairingPin,
      'deviceType': deviceType,
      'firmwareVersion': firmwareVersion,
    };
  }
}

class PairDeviceResponse {
  final String deviceId;
  final String deviceToken;
  final String elderProfileId;
  final String fullName;

  PairDeviceResponse({
    required this.deviceId,
    required this.deviceToken,
    required this.elderProfileId,
    required this.fullName,
  });

  factory PairDeviceResponse.fromJson(Map<String, dynamic> json) {
    return PairDeviceResponse(
      deviceId: json['deviceId'] as String? ?? '',
      deviceToken: json['deviceToken'] as String? ?? '',
      elderProfileId: json['elderProfileId'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
    );
  }
}

class HeartbeatRequest {
  final int? batteryPercentage;
  final bool? onBody;

  HeartbeatRequest({
    this.batteryPercentage,
    this.onBody,
  });

  Map<String, dynamic> toJson() {
    return {
      if (batteryPercentage != null) 'batteryPercentage': batteryPercentage,
      if (onBody != null) 'onBody': onBody,
    };
  }
}

class DeviceActiveIncidentResponse {
  final bool hasActiveIncident;
  final String? incidentId;
  final String status; // 'OPEN' | 'ACKNOWLEDGED' | 'RESOLVED' | 'NONE'
  final String? emergencyType;
  final DateTime? triggeredAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedByName;
  final String? acknowledgedNote;
  final DateTime? resolvedAt;
  final String? resolvedByName;
  final String? resolutionNotes;

  DeviceActiveIncidentResponse({
    required this.hasActiveIncident,
    this.incidentId,
    required this.status,
    this.emergencyType,
    this.triggeredAt,
    this.acknowledgedAt,
    this.acknowledgedByName,
    this.acknowledgedNote,
    this.resolvedAt,
    this.resolvedByName,
    this.resolutionNotes,
  });

  factory DeviceActiveIncidentResponse.fromJson(Map<String, dynamic> json) {
    return DeviceActiveIncidentResponse(
      hasActiveIncident: json['hasActiveIncident'] as bool? ?? false,
      incidentId: json['incidentId'] as String?,
      status: (json['status'] as String? ?? 'NONE').toUpperCase(),
      emergencyType: json['emergencyType'] as String?,
      triggeredAt: json['triggeredAt'] != null ? DateTime.tryParse(json['triggeredAt'] as String) : null,
      acknowledgedAt: json['acknowledgedAt'] != null ? DateTime.tryParse(json['acknowledgedAt'] as String) : null,
      acknowledgedByName: json['acknowledgedByName'] as String?,
      acknowledgedNote: json['acknowledgedNote'] as String?,
      resolvedAt: json['resolvedAt'] != null ? DateTime.tryParse(json['resolvedAt'] as String) : null,
      resolvedByName: json['resolvedByName'] as String?,
      resolutionNotes: json['resolutionNotes'] as String?,
    );
  }
}
