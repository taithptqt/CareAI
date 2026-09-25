import 'telemetry_sample.dart';

class SosPacketRequest {
  final String packetId;
  final String? eventId;
  final String emergencyType;
  final String? severity;
  final DateTime? triggeredAt;
  final String? gpsLocation;
  final bool? gpsIsSimulated;
  final double? gpsAccuracyMeters;
  final List<TelemetrySample>? samples;

  SosPacketRequest({
    required this.packetId,
    this.eventId,
    required this.emergencyType,
    this.severity,
    this.triggeredAt,
    this.gpsLocation,
    this.gpsIsSimulated,
    this.gpsAccuracyMeters,
    this.samples,
  });

  Map<String, dynamic> toJson() {
    return {
      'packetId': packetId,
      if (eventId != null) 'eventId': eventId,
      'emergencyType': emergencyType,
      if (severity != null) 'severity': severity,
      'triggeredAt': (triggeredAt ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      if (gpsLocation != null) 'gpsLocation': gpsLocation,
      if (gpsIsSimulated != null) 'gpsIsSimulated': gpsIsSimulated,
      if (gpsAccuracyMeters != null) 'gpsAccuracyMeters': gpsAccuracyMeters,
      if (samples != null)
        'samples': samples!.map((s) => s.toJson()).toList(),
    };
  }

  factory SosPacketRequest.fromJson(Map<String, dynamic> json) {
    return SosPacketRequest(
      packetId: json['packetId'] as String,
      eventId: json['eventId'] as String?,
      emergencyType: json['emergencyType'] as String? ?? 'MANUAL_SOS',
      severity: json['severity'] as String?,
      triggeredAt: json['triggeredAt'] != null
          ? DateTime.tryParse(json['triggeredAt'] as String)
          : null,
      gpsLocation: json['gpsLocation'] as String?,
      gpsIsSimulated: json['gpsIsSimulated'] as bool?,
      gpsAccuracyMeters: (json['gpsAccuracyMeters'] as num?)?.toDouble(),
      samples: json['samples'] != null
          ? (json['samples'] as List<dynamic>)
              .map((s) => TelemetrySample.fromJson(s as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
