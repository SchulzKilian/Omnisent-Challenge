import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/detection_event.dart';
import '../data/interfaces.dart';

class MockCloudService implements CloudApiInterface {
  @override
  Future<bool> uploadBatch(List<DetectionEvent> events) async {
    if (events.isEmpty) return true;
    
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));
    debugPrint("☁️ CLOUD: Received batch of ${events.length} events.");
    
    // Simulate 90% success rate to test error handling
    return true; 
  }

  @override
  Future<List<DetectionEvent>> fetchLatestState() async {
    await Future.delayed(const Duration(seconds: 1));
    debugPrint("☁️ CLOUD: Downloaded latest sensor state.");
    return []; // Return empty or mock data
  }
}