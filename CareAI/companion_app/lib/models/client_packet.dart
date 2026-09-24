class ClientPacket {
  final int? id;
  final String packetId;
  final String packetType;
  final String payload;
  final String status;
  final int createdAt;
  final int? syncedAt;
  final int retryCount;

  ClientPacket({
    this.id,
    required this.packetId,
    required this.packetType,
    required this.payload,
    this.status = 'PENDING',
    required this.createdAt,
    this.syncedAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'packet_id': packetId,
      'packet_type': packetType,
      'payload': payload,
      'status': status,
      'created_at': createdAt,
      'synced_at': syncedAt,
      'retry_count': retryCount,
    };
  }

  factory ClientPacket.fromMap(Map<String, dynamic> map) {
    return ClientPacket(
      id: map['id'] as int?,
      packetId: map['packet_id'] as String,
      packetType: map['packet_type'] as String,
      payload: map['payload'] as String,
      status: map['status'] as String? ?? 'PENDING',
      createdAt: map['created_at'] as int,
      syncedAt: map['synced_at'] as int?,
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }
}
