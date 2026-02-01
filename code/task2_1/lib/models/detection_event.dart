import 'package:latlong2/latlong.dart';

class DetectionEvent {
  final String sensorId;
  final String messageId; 
  final LatLng position;
  final int classification; // 0-3 (0: Ganz sicher, 1: Verdächtig, 2: Problem!!)
  final int prediction; 
  final double amplitude; 
  final DateTime timestamp;
  final AudioContext audio;
  DetectionEvent({
    required this.sensorId,
    required this.messageId,
    required this.position,
    required this.classification,
    required this.prediction,
    this.amplitude = 0.0,
    required this.timestamp,
    AudioContext? audio
  }) : audio = audio ?? AudioContext();
    

  bool get isActive => DateTime.now().difference(timestamp).inMinutes < 5;
}

class AudioContext {
  final bool available;
  final String? url;
  final double? playAtSecond;
  AudioContext({this.available = false, this.url, this.playAtSecond});
}