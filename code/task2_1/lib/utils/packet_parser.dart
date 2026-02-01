import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/detection_event.dart';

class PacketParser {

  static DetectionEvent? parse(String rawData) {
    try {

      final cleanData = rawData.replaceAll(RegExp(r'[<>]'), '').trim();
      
      final parts = cleanData.split(',');
      
      if (parts.length < 6) {
        debugPrint("Parse Error: Insufficient data parts -> $rawData");
        return null;
      }

      return DetectionEvent(
        sensorId: parts[0].trim(),
        messageId: parts[1].trim(),
        position: LatLng(
          double.parse(parts[2].trim()), 
          double.parse(parts[3].trim())
        ),
        prediction: int.parse(parts[4].trim()),
        classification: int.parse(parts[5].trim()),
        amplitude: parts.length > 6 ? double.tryParse(parts[6].trim()) ?? 0.5 : 0.8,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint("Parse Exception: $e for data: $rawData");
      return null;
    }
  }
}