class TelemetrySample {
  final String metricType;
  final double value;
  final String unit;
  final DateTime timestamp;

  TelemetrySample({
    required this.metricType,
    required this.value,
    required this.unit,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'metricType': metricType,
      'value': value,
      'unit': unit,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }

  factory TelemetrySample.fromJson(Map<String, dynamic> json) {
    return TelemetrySample(
      metricType: json['metricType'] as String? ?? 'UNKNOWN',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now().toUtc()
          : DateTime.now().toUtc(),
    );
  }
}
