import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:connectivity_plus/connectivity_plus.dart'; 
import 'package:sqflite/sqflite.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models/detection_event.dart';
import 'data/sensor_repository.dart';
import 'services/receiver_service.dart';
import 'services/persistence_service.dart'; 
import 'services/real_cloud_service.dart';
import 'utils/offline_tile_provider.dart';
import 'ui/history_screen.dart';

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {

    sqfliteFfiInit();

    databaseFactory = databaseFactoryFfi;
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: DroneMonitorApp(),
  ));
}

class DroneMonitorApp extends StatefulWidget {
  const DroneMonitorApp({super.key});

  @override
  State<DroneMonitorApp> createState() => _DroneMonitorAppState();
}

class _DroneMonitorAppState extends State<DroneMonitorApp> {
  // Services
  late MockReceiverService _receiverService;
  late DatabaseService _dbService;
  late RealCloudService _cloudService;
  late SensorRepository _repository;

  // State
  List<DetectionEvent> _sensors = [];
  bool _isSyncing = false;
  bool _isReady = false;
  


  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Initialize Services
    _receiverService = MockReceiverService();
    _cloudService = RealCloudService();
    
    // Initialize DB for offline queuein
    _dbService = DatabaseService();
    await _dbService.init();

    // 2. Setup Repository
    _repository = SensorRepository(
      receiver: _receiverService,
      localDb: _dbService,
      cloudApi: _cloudService,
    );

    // 3. LISTEN TO SENSORS -> SAVE TO SQLITE IMMEDIATELLY
    _sensors = _repository.currentCache;
    _repository.liveSensors.listen((updatedSensors) {
      if (mounted) {
        setState(() => _sensors = updatedSensors);
        
        // PERSISTENCE: Save every event to disk immediately
        // This ensures if app crashes, data is safe.
        for (var event in updatedSensors) {
          _dbService.insertEvent(event);
        }
      }
      
    });
    
    

    // 4. LISTEN TO INTERNET CONNECTION (Auto-Sync)
    // As soon as we have connection, flush the DB to the Cloud
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      // If the list contains mobile, wifi, or ethernet, we are online
      bool isOnline = results.contains(ConnectivityResult.mobile) || 
                      results.contains(ConnectivityResult.wifi) || 
                      results.contains(ConnectivityResult.ethernet);

      if (isOnline) {
        print("Internet Connection Restored. Attempting Auto-Sync...");
        _attemptBatchUpload(isAuto: true);
      }
    });

    _receiverService.start();
    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  
  }

  @override
  void dispose() {
    _receiverService.stop();
    super.dispose();
  }

  // Syncing but were not complaining if it doesnt work -> robust
  Future<void> _attemptBatchUpload({bool isAuto = false}) async {
    if (_isSyncing) return; // Prevent double clicks

    // 1. Read pending events from Disk (SQLite)
    final pendingEvents = await _dbService.getUnsyncedEvents(); 
    if (pendingEvents.isEmpty) {
      if (!isAuto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No new data to sync")));
      }
      return;
    }

    if (mounted) setState(() => _isSyncing = true);

    // 2. Upload
    final success = await _cloudService.uploadBatch(pendingEvents);

    if (mounted) {
      setState(() => _isSyncing = false);
      
      if (success) {
        // 3.: Only mark as synced/delete if upload succeeded
        final ids = pendingEvents.map((e) => e.messageId).toList();
        await _dbService.markEventsAsSynced(ids); 
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isAuto ? "Auto-Synced ${ids.length} events" : "Successfully Synced!")),
        );
      } else if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sync Failed. Stored locally.")));
      }
    }
  }

  Future<void> _handleSync() async {
    await _attemptBatchUpload(isAuto: false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 20),
              Text("Initializing Sensors...", style: TextStyle(color: Colors.white))
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // --------------------------
          // LAYER 1: MAP
          // --------------------------
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(-37.837, 144.932),
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.omnisent.monitor',
                tileProvider: OfflineTileProvider(),
                tileBuilder: (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1, 0, 0, 0, 255,
                      0, -1, 0, 0, 255,
                      0, 0, -1, 0, 255,
                      0, 0, 0, 1, 0,
                    ]), 
                    child: tileWidget,
                  );
                },
              ),
              
              // Visual Range Rings
              CircleLayer(
                circles: _sensors
                    .where((s) => s.classification > 0) 
                    .map((s) => CircleMarker(
                      point: s.position,
                      color: _getColorForClass(s.classification).withOpacity(0.2),
                      borderStrokeWidth: 1,
                      borderColor: _getColorForClass(s.classification),
                      useRadiusInMeter: true,
                      radius: 300, 
                    )).toList(),
              ),

              // Sensor Icons
              MarkerLayer(
                markers: _sensors.map((s) => Marker(
                  point: s.position,
                  width: 60,
                  height: 60,
                  child: _buildSensorMarker(s),
                )).toList(),
              ),
            ],
          ),

          // --------------------------
          // LAYER 2: UI OVERLAY
          // --------------------------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderStats(),
                  const Spacer(),
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI HELPERS ---

  Color _getColorForClass(int classification) {
    switch (classification) {
      case 0: return Colors.green;   // Safe
      case 1: return Colors.orange;  // Suspicious
      case 2: return Colors.red;     // Hostile
      case -1: return Colors.grey;   // Idle
      default: return Colors.grey;
    }
  }

  Widget _buildSensorMarker(DetectionEvent s) {
    final isIdle = s.classification == -1;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _getColorForClass(s.classification),
            shape: BoxShape.circle,
            border: Border.all(
              color: isIdle ? Colors.grey[700]! : Colors.white, 
              width: 2
            ),
            boxShadow: isIdle ? [] : [
              BoxShadow(
                color: _getColorForClass(s.classification).withOpacity(0.8), 
                blurRadius: 10
              )
            ]
          ),
          child: Icon(
            Icons.radar, 
            color: isIdle ? Colors.black54 : Colors.white, 
            size: 16
          ),
        ),
        const SizedBox(height: 2),
        Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            s.sensorId, 
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 10, 
              fontWeight: FontWeight.bold
            ),
          ),
        )
      ],
    );
  }

  Widget _buildHeaderStats() {
    final activeCount = _sensors.where((s) => s.classification > 0).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Omnisent Monitor", style: TextStyle(color: Colors.grey[400], fontSize: 10)),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryScreen(
                        repository: _repository,
                        cloudService: _cloudService, 
                      ),
                    ),
                  );
                },
                child: const Row(
                  children: [
                    Icon(Icons.history, color: Colors.blue, size: 16),
                    SizedBox(width: 4),
                    Text("History", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
              const SizedBox(width: 8),
              Text(
                "Threats: $activeCount", 
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Center(
      child: ElevatedButton.icon(
        icon: _isSyncing 
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.cloud_upload, size: 18),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isSyncing ? Colors.grey : Colors.blue[900],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
        onPressed: _isSyncing ? null : _handleSync,
        label: Text(_isSyncing ? "Syncing..." : "Sync Cloud"),
      ),
    );
  }
}