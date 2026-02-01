import 'dart:async';
import 'dart:ui'; 
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/detection_event.dart';
import '../data/sensor_repository.dart';
import '../services/real_cloud_service.dart';
import '../utils/offline_tile_provider.dart';

class HistoryScreen extends StatefulWidget {
  final SensorRepository repository;
  final RealCloudService cloudService;
  
  const HistoryScreen({super.key, required this.repository, required this.cloudService});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late DateTime _windowStart;
  late DateTime _currentSliderTime;
  List<DetectionEvent> _cachedEvents = [];
  bool _isLoading = false;
  bool _isPlaying = false;
  Timer? _playbackTimer;
  List<Color> _timelineColors = [];

  final Map<String, LatLng> _fixedLocations = {
    "S1": const LatLng(-37.835, 144.930),
    "S2": const LatLng(-37.837, 144.932),
    "S3": const LatLng(-37.839, 144.935),
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _windowStart = DateTime(now.year, now.month, now.day, now.hour);
    _currentSliderTime = now; 
    _loadCurrentMemory(); 
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    super.dispose();
  }


  DateTime get _playableLimit {
    final now = DateTime.now();
    final windowEnd = _windowStart.add(const Duration(hours: 1));
    // If the window ends in the future, the limit is NOW. Otherwise, it's the end of the window.
    return windowEnd.isAfter(now) ? now : windowEnd;
  }

  void _loadCurrentMemory() {
    setState(() => _isLoading = true);
    final targetEnd = _windowStart.add(const Duration(hours: 1));
    final memoryEvents = widget.repository.fullHistory.where((e) => 
      e.timestamp.isAfter(_windowStart) && e.timestamp.isBefore(targetEnd)
    ).toList();

    setState(() {
      _cachedEvents = memoryEvents;
      _cachedEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _generateTimelineColors();
      _isLoading = false;
    });
  }
// --- HIGHER RESOLUTION & ACCURATE ALIGNMENT ---
  void _generateTimelineColors() {
    if (_cachedEvents.isEmpty) {
      _timelineColors = [];
      return;
    }


    const int segments = 300;
    

    List<int> buckets = List.filled(segments, -2);

    final int totalMillis = const Duration(hours: 1).inMilliseconds;
    
    // 1. FAST SWEEP (O(N)): Loop through events once and drop them into buckets
    for (var event in _cachedEvents) {
      final diff = event.timestamp.difference(_windowStart).inMilliseconds;
      
      // Safety check: ignore alllll events outside this hour window
      if (diff < 0 || diff >= totalMillis) continue;

      // Calculate exact bucket index
      final int index = (diff / totalMillis * segments).floor();
      
      if (index >= 0 && index < segments) {

        if (event.classification > buckets[index]) {
          buckets[index] = event.classification;
        }
      }
    }

    // 2. CONVERT TO COLORS

    _timelineColors = buckets.map((classId) {
      if (classId == -2) return Colors.grey[900]!; 
      return _getColor(classId);
    }).toList();
  }

  Future<void> _attemptWindowChange(int offsetHours) async {
    if (_isLoading) return;
    final targetStart = _windowStart.add(Duration(hours: offsetHours));
    final targetEnd = targetStart.add(const Duration(hours: 1));
    
    // You cant see the future....
    if (targetStart.isAfter(DateTime.now())) return;

    final now = DateTime.now();
    final isCurrentWindow = targetStart.isBefore(now) && targetEnd.isAfter(now);

    setState(() => _isLoading = true);
    try {
      List<DetectionEvent> newEvents = [];
      if (isCurrentWindow) {
        newEvents = widget.repository.fullHistory.where((e) => e.timestamp.isAfter(targetStart) && e.timestamp.isBefore(targetEnd)).toList();
        await Future.delayed(const Duration(milliseconds: 100));
      } else {
        newEvents = await widget.cloudService.fetchHistoryWindow(targetStart, targetEnd);
      }

      if (mounted) {
        setState(() {
          _windowStart = targetStart;
          _cachedEvents = newEvents;
          _cachedEvents.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          
          _currentSliderTime = isCurrentWindow ? DateTime.now() : _windowStart;
          
          _generateTimelineColors();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Playback ---
  void _togglePlay() {
    if (_isPlaying) { 
      _playbackTimer?.cancel(); 
      setState(() => _isPlaying = false); 
    } else {
      // Don't start playing if we are already at the limit
      if (_currentSliderTime.isAtSameMomentAs(_playableLimit) || _currentSliderTime.isAfter(_playableLimit)) {
        setState(() => _currentSliderTime = _windowStart); // Restart from beginning
      }

      setState(() => _isPlaying = true);
      _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
        if (!mounted) return;
        setState(() {
          // Speed: realtime speed. One can change this in the future or add in a speed dial
          final step = 10 * 10; 
          final next = _currentSliderTime.add(Duration(milliseconds: step));
          
          // Are we at the real time now?
          if (next.isAfter(_playableLimit)) {
             _currentSliderTime = _playableLimit; 
             _isPlaying = false; 
             t.cancel(); 
          } else { 
            _currentSliderTime = next; 
          }
        });
      });
    }
  }

  List<DetectionEvent> _getVisualStateAt(DateTime time) {
    final windowBottom = time.subtract(const Duration(seconds: 5));
    final activeEvents = _cachedEvents.where((e) => e.timestamp.isAfter(windowBottom) && e.timestamp.isBefore(time)).toList();
    List<DetectionEvent> finalVisuals = [];
    _fixedLocations.forEach((sensorId, position) {
      try { finalVisuals.add(activeEvents.lastWhere((e) => e.sensorId == sensorId)); } 
      catch (e) { finalVisuals.add(DetectionEvent(sensorId: sensorId, messageId: "idle", position: position, classification: -1, prediction: 0, timestamp: time)); }
    });
    return finalVisuals;
  }
  
  Color _getColor(int c) => c==2?Colors.red : c==1?Colors.orange : c==0?Colors.green : Colors.grey;

  @override
  Widget build(BuildContext context) {
    final windowEnd = _windowStart.add(const Duration(hours: 1));
    final sliderProgress = _currentSliderTime.difference(_windowStart).inMilliseconds / const Duration(hours: 1).inMilliseconds;
    final currentSensorStates = _getVisualStateAt(_currentSliderTime);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("History", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _isLoading ? null : () => _attemptWindowChange(-1)),
          Center(child: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text("${_windowStart.hour}:00 - ${windowEnd.hour}:00", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
          IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _isLoading ? null : () => _attemptWindowChange(1)),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: FlutterMap(
            options: const MapOptions(initialCenter: LatLng(-37.837, 144.932), initialZoom: 14.5),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', tileProvider: OfflineTileProvider(),
                tileBuilder: (c, w, t) => ColorFiltered(colorFilter: const ColorFilter.matrix([-1,0,0,0,255, 0,-1,0,0,255, 0,0,-1,0,255, 0,0,0,1,0]), child: w)
              ),
              CircleLayer(circles: currentSensorStates.where((s) => s.classification > 0).map((s) => CircleMarker(
                point: s.position, color: _getColor(s.classification).withOpacity(0.2), borderColor: _getColor(s.classification), useRadiusInMeter: true, radius: 300)).toList()),
              MarkerLayer(markers: currentSensorStates.map((s) => Marker(point: s.position, width: 60, height: 60, child: _buildMarker(s))).toList()),
            ],
          )),
          Container(
            color: Colors.grey[900], padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("Replay: ${_currentSliderTime.hour}:${_currentSliderTime.minute}:${_currentSliderTime.second}", 
                     style: const TextStyle(color: Colors.white, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
                IconButton(icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow), color: Colors.white, onPressed: _togglePlay)
              ]),
              


              // 1. TIMELINE BAR
              Padding(
                // We need this padding because the slider has automatic padding, this way we match the timeline and the slider
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: _timelineColors.map((c) => Expanded(child: Container(color: c))).toList(),
                  ),
                ),
              ),

              // 2. SLIDER
              Slider(
                value: sliderProgress.clamp(0.0, 1.0),
                onChanged: (val) {
                  setState(() {
                    final millis = (val * const Duration(hours: 1).inMilliseconds).round();
                    DateTime newTime = _windowStart.add(Duration(milliseconds: millis));
                    if (newTime.isAfter(_playableLimit)) newTime = _playableLimit;
                    _currentSliderTime = newTime;
                  });
                },
              ),
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildMarker(DetectionEvent s) {
    bool idle = s.classification == -1;
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: _getColor(s.classification), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2), boxShadow: idle?[]:[BoxShadow(color: _getColor(s.classification).withOpacity(0.8), blurRadius: 10)]), child: Icon(Icons.radar, color: idle?Colors.black54:Colors.white, size: 16)),
      const SizedBox(height: 2), Container(decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), child: Text(s.sensorId, style: const TextStyle(color: Colors.white, fontSize: 10)))
    ]);
  }
}