import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'; // Core map logic
import 'package:path_provider/path_provider.dart'; // To find where to save files
import 'package:http/http.dart' as http; // To download tiles
import 'dart:ui' as ui;

class OfflineTileProvider extends TileProvider {
  // We mock a generic header (like a browser) to avoid getting blocked by OSM
  @override
  Map<String, String> get headers => {'User-Agent': 'OmnisentMonitor/1.0'};

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // 1. Calculate the target file path: .../tiles/14/120/405.png
    final targetPath = _getTileFilePath(coordinates, options);

    // 2. Return a custom ImageProvider that handles the "Check -> Download -> Save" logic
    return _OfflineTileImage(
      url: getTileUrl(coordinates, options),
      fallbackPath: targetPath,
      headers: headers,
    );
  }

  Future<File> _getTileFilePath(TileCoordinates coords, TileLayer options) async {
    final docDir = await getApplicationDocumentsDirectory();
    final z = coords.z;
    final x = coords.x;
    final y = coords.y;
    
    // Create directory structure: documents/offline_tiles/z/x/
    final saveDir = Directory('${docDir.path}/offline_tiles/$z/$x');
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    return File('${saveDir.path}/$y.png');
  }
}

// Custom Image Provider to handle the async "File vs Network" logic
class _OfflineTileImage extends ImageProvider<_OfflineTileImage> {
  final String url;
  final Future<File> fallbackPath;
  final Map<String, String> headers;

  _OfflineTileImage({required this.url, required this.fallbackPath, required this.headers});

  @override
  Future<_OfflineTileImage> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(_OfflineTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
      informationCollector: () => [DiagnosticsProperty('URL', url)],
    );
  }

  Future<ui.Codec> _loadAsync(_OfflineTileImage key, ImageDecoderCallback decode) async {
    try {
      final file = await key.fallbackPath;

      // A. CHECK LOCAL DISK
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
           // Success! Loaded from disk.
          return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
        }
      }

      // B. DOWNLOAD FROM NETWORK (If not found locally)
      final uri = Uri.parse(key.url);
      final response = await http.get(uri, headers: key.headers);

      if (response.statusCode == 200) {
        // C. SAVE TO DISK (For next time)
        await file.writeAsBytes(response.bodyBytes);
        
        return await decode(await ui.ImmutableBuffer.fromUint8List(response.bodyBytes));
      } else {
        throw Exception('Failed to load tile: ${response.statusCode}');
      }
    } catch (e) {
      // D. ERROR HANDLING (Return a transparent pixel or retry logic)
      // For this demo, we rethrow so the map shows the error placeholder.
      throw Exception('Tile load failed: $e');
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _OfflineTileImage && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

