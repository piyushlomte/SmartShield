import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/chat_message.dart';

class DbService {
  static final DbService instance = DbService._init();
  static Database? _database;

  DbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mesh_sos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        sender_id INTEGER NOT NULL,
        recipient_id INTEGER NOT NULL,
        text TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        is_outgoing INTEGER NOT NULL,
        status TEXT NOT NULL,
        rssi INTEGER,
        snr REAL,
        channel TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE contacts (
        node_id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        custom_name TEXT,
        is_favorite INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> insertMessage(ChatMessage message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> getMessages({String channel = 'Public'}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'channel = ?',
      whereArgs: [channel],
      orderBy: 'timestamp ASC',
    );
    return List.generate(maps.length, (i) => ChatMessage.fromMap(maps[i]));
  }

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
