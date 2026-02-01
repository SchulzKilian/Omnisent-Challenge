import 'dart:async';
import 'dart:math';
import 'package:latlong2/latlong.dart';

abstract class ReceiverInterface {
  Stream<String> get rawPacketStream;
  void start();
  void stop();
}

// This is the implementation that fakes the data
class MockReceiverService implements ReceiverInterface {
  final _controller = StreamController<String>.broadcast();
  Timer? _timer;
  final Random _rng = Random();

  // Fixed locations for sensors because the sensors are going to be fixed by us at specific points, they dont need to come from the user API necessarily
  final Map<String, LatLng> _fixedSensors = {
    "S1": const LatLng(-37.835, 144.930),
    "S2": const LatLng(-37.837, 144.932),
    "S3": const LatLng(-37.839, 144.935),
  };

@override
  void start() {
    // Generate a packet every 1.5 seconds
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      final sensorId = "S${_rng.nextInt(3) + 1}"; 
      final location = _fixedSensors[sensorId]!;
      final msgId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Not important to production but we randomly mock whatever the hell the sensors see
      int classification;
      double roll = _rng.nextDouble(); 

      if (roll < 0.85) {
        classification = 0; // 85% chance of GREEN
      } else if (roll < 0.9) {
        classification = -1; // 5% chance of GREY (Idle)
      } else if (roll < 0.95) {
        classification = 1; // 5% chance of ORANGE
      } else {
        classification = 2; // 5% chance of RED
      }

      final prediction = (classification == 1 || classification == 2) ? 1 : 0;

      final packet = "<$sensorId, $msgId, ${location.latitude}, ${location.longitude}, $prediction, $classification>";
      _controller.add(packet);
    });
  }
  @override
  void stop() {
    _timer?.cancel();
  }

  @override
  Stream<String> get rawPacketStream => _controller.stream;
}