import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:latlong2/latlong.dart';
import '../models/detection_event.dart';
import '../data/interfaces.dart';


class DatabaseService implements LocalDatabaseInterface {
  
  static Database? _database;
  
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  @override
  Future<void> init() async {
    if (_database != null) return;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'omnisent_v1.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {

        await db.execute('''
          CREATE TABLE events (
            messageId TEXT PRIMARY KEY,
            sensorId TEXT NOT NULL,
            lat REAL,
            lng REAL,
            classification INTEGER,
            prediction INTEGER,
            amplitude REAL,
            timestamp TEXT NOT NULL,
            is_synced INTEGER DEFAULT 0 
          )
        ''');
        
        // Index for fast "Latest State" queries
        await db.execute('CREATE INDEX idx_sensor_time ON events(sensorId, timestamp DESC)');
      },
    );
  }

  Future<Database> get _db async {
    if (_database == null) await init();
    return _database!;
  }

  @override
  Future<void> insertEvent(DetectionEvent event) async {
    final db = await _db;
    await db.insert(
      'events',
      {
        'messageId': event.messageId,
        'sensorId': event.sensorId,
        'lat': event.position.latitude,
        'lng': event.position.longitude,
        'classification': event.classification,
        'prediction': event.prediction,
        'amplitude': event.amplitude,
        'timestamp': event.timestamp.toIso8601String(),
        'is_synced': 0, // Defaults to 0 (Unsynced)
      },
      // If we receive the same packet twice, we ignore the second one
      conflictAlgorithm: ConflictAlgorithm.ignore, 
    );
  }

  @override
  Future<List<DetectionEvent>> getUnsyncedEvents() async {
    final db = await _db;
    
    // Get all rows where is_synced is 0 (False)
    final List<Map<String, dynamic>> maps = await db.query(
      'events',
      where: 'is_synced = ?',
      whereArgs: [0],
    );

    return maps.map((row) => _mapToEvent(row)).toList();
  }

  @override
  Future<void> markEventsAsSynced(List<String> messageIds) async {
    final db = await _db;
    
    // Efficiently update multiple rows
    // For production this should be batched, but for a 50 sensor task i think Im fine
    await db.update(
      'events',
      {'is_synced': 1},
      where: 'messageId IN (${List.filled(messageIds.length, '?').join(',')})',
      whereArgs: messageIds,
    );
  }
  
  @override
  Future<List<DetectionEvent>> getLatestSensorState() async {
    final db = await _db;
    

    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT * FROM events 
      WHERE timestamp IN (
        SELECT MAX(timestamp) 
        FROM events 
        GROUP BY sensorId
      )
    ''');

    return rows.map((row) => _mapToEvent(row)).toList();
  }

  // Helper to convert DB Row -> Dart Object
  DetectionEvent _mapToEvent(Map<String, dynamic> row) {
    return DetectionEvent(
      sensorId: row['sensorId'],
      messageId: row['messageId'],
      position: LatLng(row['lat'], row['lng']),
      classification: row['classification'],
      prediction: row['prediction'],
      amplitude: row['amplitude'],
      timestamp: DateTime.parse(row['timestamp']),
    );
  }
}