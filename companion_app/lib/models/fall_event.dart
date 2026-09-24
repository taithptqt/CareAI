class FallEvent {
  final String eventId;
  final int timestamp;
  final double? impactG;
  final int secondsRemaining;
  final bool isFromHardwareWatch;

  FallEvent({
    required this.eventId,
    required this.timestamp,
    this.impactG,
    required this.secondsRemaining,
    required this.isFromHardwareWatch,
  });

  factory FallEvent.fromMap(Map<String, dynamic> map, {bool isHardware = true}) {
    return FallEvent(
      eventId: map['eventId'] as String? ?? 'FALL_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      impactG: (map['impactG'] as num?)?.toDouble(),
      secondsRemaining: (map['secondsRemaining'] as num?)?.toInt() ?? 30,
      isFromHardwareWatch: isHardware,
    );
  }
}
