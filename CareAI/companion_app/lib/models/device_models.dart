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
