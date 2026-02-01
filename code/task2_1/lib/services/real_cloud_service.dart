import 'dart:convert';
import 'dart:io'; 
import 'package:flutter/foundation.dart'; 
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data/interfaces.dart';
import '../models/detection_event.dart';

class RealCloudService implements CloudApiInterface {

  String get baseUrl {
    if (kIsWeb) return "http://localhost:8000";
    if (Platform.isAndroid) return "http://10.0.2.2:8000"; // Android Emulator 
    return "http://127.0.0.1:8000"; // iOS / Desktop
  }



  @override
  Future<bool> uploadBatch(List<DetectionEvent> events) async {
    try {
      print("Trying to upload");
      final url = Uri.parse('$baseUrl/events/batch');
      final body = jsonEncode(events.map((e) => {
        "sensorId": e.sensorId,
        "messageId": e.messageId,
        "position": {"lat": e.position.latitude, "lng": e.position.longitude},
        "classification": e.classification,
        "prediction": e.prediction,
        "amplitude": e.amplitude,
        "timestamp": e.timestamp.toIso8601String(),
      }).toList());

      final response = await http.post(
        url, 
        headers: {"Content-Type": "application/json"},
        body: body
      );
      print(response.body);

      return response.statusCode == 200;
    } catch (e) {
      print("Upload failed: $e");
      return false;
    }
  }

  // Fetch events between start and end DateTimes
  Future<List<DetectionEvent>> fetchHistoryWindow(DateTime start, DateTime end) async {
    try {
      final url = Uri.parse('$baseUrl/events/window?start_iso=${start.toIso8601String()}&end_iso=${end.toIso8601String()}');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => DetectionEvent(
          sensorId: json['sensorId'],
          messageId: json['messageId'],
          position: LatLng(json['position']['lat'], json['position']['lng']),
          classification: json['classification'],
          prediction: json['prediction'],
          amplitude: json['amplitude'] ?? 0.0,
          timestamp: DateTime.parse(json['timestamp']),
        )).toList();
      }
      throw Exception("Server Error: ${response.statusCode}");
    } catch (e) {
      print("Fetch history failed: $e");
      rethrow; // We still want to throw an error so the UI can handle it
    }
  }

  @override
  Future<List<DetectionEvent>> fetchLatestState() async {
    return []; 
  }
}