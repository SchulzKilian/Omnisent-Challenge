import 'dart:async';
import '../models/detection_event.dart';
import '../data/interfaces.dart';

class MockDatabaseService implements LocalDatabaseInterface {

  final List<DetectionEvent> _tableEvents = [];
  final Set<String> _syncedMessageIds = {};

  @override
  Future<void> init() async {
    // simulate opening DB connection
    await Future.delayed(const Duration(milliseconds: 100)); 
  }

  @override
  Future<void> insertEvent(DetectionEvent event) async {
    _tableEvents.add(event);
    // In real life: await db.insert('events', event.toMap());
  }

  @override
  Future<List<DetectionEvent>> getUnsyncedEvents() async {
    // Return events whose IDs are NOT in the synced set
    return _tableEvents.where((e) => !_syncedMessageIds.contains(e.messageId)).toList();
  }

  @override
  Future<void> markEventsAsSynced(List<String> messageIds) async {
    _syncedMessageIds.addAll(messageIds);
  }
  
  @override
  Future<List<DetectionEvent>> getLatestSensorState() async {
    // Logic to find the newest event per sensorID
    // In SQL: SELECT * FROM events GROUP BY sensorId ORDER BY timestamp DESC
    final Map<String, DetectionEvent> latest = {};
    for (var event in _tableEvents) {
      latest[event.sensorId] = event; // Simple overwrite works if list is ordered
    }
    return latest.values.toList();
  }
}