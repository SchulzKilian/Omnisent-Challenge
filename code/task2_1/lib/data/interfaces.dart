import '../models/detection_event.dart';

// 1. PERSISTENCE INTERFACE (Saves data on the phone)
abstract class LocalDatabaseInterface {
  Future<void> init();
  Future<void> insertEvent(DetectionEvent event);
  Future<List<DetectionEvent>> getUnsyncedEvents();
  Future<void> markEventsAsSynced(List<String> messageIds);
  Future<List<DetectionEvent>> getLatestSensorState();
}

// 2. CLOUD INTERFACE (Talks to the internet)
abstract class CloudApiInterface {
  Future<bool> uploadBatch(List<DetectionEvent> events);
  Future<List<DetectionEvent>> fetchLatestState();
}