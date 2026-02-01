import 'dart:async';
import 'package:latlong2/latlong.dart';
import '../models/detection_event.dart';
import '../utils/packet_parser.dart';
import '../services/receiver_service.dart';
import '../services/persistence_service.dart'; // Ensure these match your actual filenames
import '../services/cloud_service.dart';       // Ensure these match your actual filenames
import '../data/interfaces.dart';              // Ensure these match your actual filenames

class SensorRepository {
  final ReceiverInterface receiver;
  final LocalDatabaseInterface localDb;
  final CloudApiInterface cloudApi;

  // --- 1. THE EVENT LOG (This is where history lives) ---
  final List<DetectionEvent> _eventLog = []; 
  
  // The latest status of every sensor (for the live Map)
  final Map<String, DetectionEvent> _latestState = {}; 

  // Stream to notify UI of updates
  final StreamController<List<DetectionEvent>> _uiStream = StreamController.broadcast();

  // Hardcoded locations to prevent map jumping
  final Map<String, LatLng> _fixedLocations = {
    "S1": const LatLng(-37.835, 144.930),
    "S2": const LatLng(-37.837, 144.932),
    "S3": const LatLng(-37.839, 144.935),
  };

  SensorRepository({
    required this.receiver,
    required this.localDb,
    required this.cloudApi,
  }) {
    _initialize();
  }

  Future<void> _initialize() async {
    await localDb.init();
    
    // Load initial state from Local DB (Offline First!)
    final cachedEvents = await localDb.getLatestSensorState();
    if (cachedEvents.isEmpty) {
      _initializeFixedSensors(); 
    } else {
      for (var e in cachedEvents) {
        _latestState[e.sensorId] = e;
      }
      _uiStream.add(_latestState.values.toList());
    }

    // Listen to Live OTG Data
    receiver.rawPacketStream.listen(_handleIncomingPacket);
  }

  void _initializeFixedSensors() {
    _fixedLocations.forEach((id, pos) {
      _latestState[id] = DetectionEvent(
        sensorId: id,
        messageId: "init_$id",
        position: pos,
        classification: -1, // Grey/Idle
        prediction: 0,
        timestamp: DateTime.now(),
      );
    });
    _uiStream.add(_latestState.values.toList());
  }

  Future<void> _handleIncomingPacket(String rawString) async {
    final event = PacketParser.parse(rawString);
    if (event == null) return;

    // Force Location Lock
    final fixedEvent = DetectionEvent(
      sensorId: event.sensorId,
      messageId: event.messageId,
      position: _fixedLocations[event.sensorId] ?? event.position, 
      classification: event.classification,
      prediction: event.prediction,
      amplitude: event.amplitude,
      timestamp: event.timestamp,
    );

    // --- 2. POPULATE EVENT LOG ---
    // This is where we save the history for the replay slider
    _eventLog.add(fixedEvent);

    // Save to Local DB (Persistence)
    await localDb.insertEvent(fixedEvent);

    // Update Live Map State
    _latestState[fixedEvent.sensorId] = fixedEvent;
    _uiStream.add(_latestState.values.toList());
  }

  /// Triggered manually by user or background timer
  Future<void> syncToCloud() async {
    final pending = await localDb.getUnsyncedEvents();
    if (pending.isEmpty) return;

    final success = await cloudApi.uploadBatch(pending);
    if (success) {
      final ids = pending.map((e) => e.messageId).toList();
      await localDb.markEventsAsSynced(ids);
    } 
  }

  // --- PUBLIC API FOR UI ---

  Stream<List<DetectionEvent>> get liveSensors => _uiStream.stream;
  List<DetectionEvent> get currentCache => _latestState.values.toList();

  // --- NEW METHODS FOR HISTORY SCREEN ---

  // 3. Expose the full history log
  List<DetectionEvent> get fullHistory => List.unmodifiable(_eventLog);

  // 4. Calculate what the world looked like at a specific time
  List<DetectionEvent> getSnapshotAt(DateTime time) {
    final Map<String, DetectionEvent> snapshot = {};
    
    // Sort events by time to replay them in correct order
    final sortedEvents = List<DetectionEvent>.from(_eventLog)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (var event in sortedEvents) {
      if (event.timestamp.isAfter(time)) break; // Stop if we pass the target time
      snapshot[event.sensorId] = event; // Update sensor state
    }
    
    // Ensure we return the "latest known state" for every sensor found
    return snapshot.values.toList();
  }
}