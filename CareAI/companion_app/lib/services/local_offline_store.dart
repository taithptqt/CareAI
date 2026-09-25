import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/client_packet.dart';

class LocalOfflineStore {
  static final LocalOfflineStore instance = LocalOfflineStore._init();
  static Database? _database;

  LocalOfflineStore._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('careai_local_spool.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        // Chế độ WAL (Write-Ahead Logging) cho tốc độ ghi cao và đọc song song
        // Lưu ý: PRAGMA journal_mode trả về kết quả ('wal') nên trên Android bắt buộc dùng rawQuery thay vì execute
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
      },
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE client_packets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packet_id TEXT UNIQUE NOT NULL,
        packet_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING',
        synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        retry_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Index cho truy vấn gói tin pending nhanh chóng
    await db.execute('''
      CREATE INDEX idx_client_packets_status_created 
      ON client_packets (status, created_at)
    ''');

    await db.execute('''
      CREATE INDEX idx_client_packets_synced 
      ON client_packets (synced, created_at)
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE client_packets ADD COLUMN synced INTEGER NOT NULL DEFAULT 0");
        await db.execute("UPDATE client_packets SET synced = CASE WHEN status = 'SYNCED' THEN 1 ELSE 0 END");
      } catch (_) {}
    }
  }

  /// Ghi gói tin vào Outbox đĩa (Outbox-First Pattern)
  /// Sử dụng INSERT OR IGNORE để chống trùng lặp theo packet_id
  Future<bool> enqueuePacket({
    required String packetId,
    required String packetType,
    required String payload,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insert(
      'client_packets',
      {
        'packet_id': packetId,
        'packet_type': packetType,
        'payload': payload,
        'status': 'PENDING',
        'synced': 0,
        'created_at': now,
        'retry_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    return id > 0;
  }

  /// Lấy danh sách gói tin PENDING để đồng bộ lên máy chủ
  Future<List<ClientPacket>> getPendingPackets({int limit = 50}) async {
    final db = await database;
    final maps = await db.query(
      'client_packets',
      where: 'status = ? OR synced = 0',
      whereArgs: ['PENDING'],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return maps.map((m) => ClientPacket.fromMap(m)).toList();
  }

  /// Đánh dấu gói tin đã gửi thành công
  Future<void> markPacketSynced(String packetId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'client_packets',
      {
        'status': 'SYNCED',
        'synced': 1,
        'synced_at': now,
      },
      where: 'packet_id = ?',
      whereArgs: [packetId],
    );
  }

  /// Đánh dấu thất bại và tăng biến đếm thử lại
  Future<void> markPacketFailed(String packetId) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE client_packets 
      SET retry_count = retry_count + 1 
      WHERE packet_id = ?
    ''', [packetId]);
  }

  /// Lấy số lượng gói tin đang chờ đồng bộ
  Future<int> getPendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM client_packets WHERE status = 'PENDING' OR synced = 0"
    );
    if (result.isNotEmpty) {
      return (result.first['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Cập nhật con trỏ High-Water Mark (last_sync_timestamp)
  Future<void> setLastSyncTimestamp(DateTime timestamp) async {
    final db = await database;
    await db.insert(
      'sync_metadata',
      {
        'key': 'last_sync_timestamp',
        'value': timestamp.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Đọc con trỏ High-Water Mark
  Future<DateTime?> getLastSyncTimestamp() async {
    final db = await database;
    final maps = await db.query(
      'sync_metadata',
      where: 'key = ?',
      whereArgs: ['last_sync_timestamp'],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      final str = maps.first['value'] as String?;
      if (str != null) return DateTime.tryParse(str);
    }
    return null;
  }

  /// Dọn dẹp các gói tin đã đồng bộ (Synced = 1) cũ hơn 7 ngày để tránh phình dung lượng.
  /// BẤT BIẾN FACT 33 & 34: TUYỆT ĐỐI KHÔNG GỌI db.execute('VACUUM') ĐỂ TRÁNH MÒN BỘ NHỚ FLASH.
  Future<int> purgeOldSyncedPackets({int retentionDays = 7}) async {
    final db = await database;
    final cutoffMillis = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .millisecondsSinceEpoch;

    return await db.delete(
      'client_packets',
      where: '(status = ? OR synced = 1) AND (synced_at < ? OR (synced_at IS NULL AND created_at < ?))',
      whereArgs: ['SYNCED', cutoffMillis, cutoffMillis],
    );
  }

  /// Alias tương thích ngược
  Future<int> pruneOldSyncedPackets({int retentionDays = 7}) =>
      purgeOldSyncedPackets(retentionDays: retentionDays);
}
