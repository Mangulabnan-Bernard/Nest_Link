import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// Valid, identifying User-Agent (required by tile providers' policies).
const _userAgent = 'NestLink/1.0 (+https://github.com/Mangulabnan-Bernard/Nest_Link)';

/// CARTO dark basemap — free, fits the charcoal theme, and a separate server
/// from OSM's (which blocks heavy use). Attribution: © OpenStreetMap, © CARTO.
const tileUrlTemplate = 'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
String _tileUrl(int z, int x, int y) =>
    'https://a.basemaps.cartocdn.com/dark_all/$z/$x/$y.png';

/// Offline map tile cache. Tiles you view (or pre-download) are saved to disk,
/// so the map still renders with no internet.
class TileCache {
  TileCache._();
  static final TileCache instance = TileCache._();

  Directory? _dir;

  Future<Directory> ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/map_tiles');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  File fileFor(Directory d, int z, int x, int y) => File('${d.path}/${z}_${x}_$y.png');

  // ── slippy-map tile math ──
  static int lonToX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor().clamp(0, (1 << z) - 1);

  static int latToY(double lat, int z) {
    final r = lat * math.pi / 180.0;
    return ((1.0 - (math.log(math.tan(r) + 1 / math.cos(r)) / math.pi)) / 2.0 * (1 << z))
        .floor()
        .clamp(0, (1 << z) - 1);
  }

  int countTiles(LatLngBounds b, int zMin, int zMax) {
    var total = 0;
    for (var z = zMin; z <= zMax; z++) {
      final x1 = lonToX(b.west, z), x2 = lonToX(b.east, z);
      final y1 = latToY(b.north, z), y2 = latToY(b.south, z);
      total += ((x2 - x1).abs() + 1) * ((y2 - y1).abs() + 1);
    }
    return total;
  }

  /// Download + save all tiles for [bounds] across [zMin]..[zMax].
  /// Download tiles politely: rate-limited and capped, to respect the OSM
  /// volunteer tile-server policy (no fast bulk downloads).
  Future<void> downloadArea(
    LatLngBounds bounds,
    int zMin,
    int zMax, {
    required void Function(int done, int total) onProgress,
    int maxTiles = 250,
  }) async {
    final d = await ensureDir();
    final total = math.min(countTiles(bounds, zMin, zMax), maxTiles);
    var done = 0;
    for (var z = zMin; z <= zMax && done < total; z++) {
      final xs = [lonToX(bounds.west, z), lonToX(bounds.east, z)]..sort();
      final ys = [latToY(bounds.north, z), latToY(bounds.south, z)]..sort();
      for (var x = xs.first; x <= xs.last && done < total; x++) {
        for (var y = ys.first; y <= ys.last && done < total; y++) {
          final f = fileFor(d, z, x, y);
          if (!await f.exists()) {
            try {
              final resp = await http.get(
                Uri.parse(_tileUrl(z, x, y)),
                headers: const {'User-Agent': _userAgent},
              );
              if (resp.statusCode == 200) await f.writeAsBytes(resp.bodyBytes);
              // be a good citizen: throttle to well under the policy limits
              await Future.delayed(const Duration(milliseconds: 200));
            } catch (_) {}
          }
          done++;
          onProgress(done, total);
        }
      }
    }
  }
}

/// flutter_map provider that serves tiles from the disk cache, falling back to
/// the network (and caching the result) when a tile is missing.
class CachedTileProvider extends TileProvider {
  final Directory cacheDir;
  CachedTileProvider(this.cacheDir);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    final file = TileCache.instance.fileFor(cacheDir, coordinates.z, coordinates.x, coordinates.y);
    return _CachedTileImage(url, file);
  }
}

class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  final String url;
  final File file;
  _CachedTileImage(this.url, this.file);

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_CachedTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1.0);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    Uint8List bytes;
    if (await file.exists()) {
      bytes = await file.readAsBytes();
    } else {
      final resp = await http.get(Uri.parse(url), headers: const {'User-Agent': _userAgent});
      bytes = resp.bodyBytes;
      if (resp.statusCode == 200) {
        try {
          await file.create(recursive: true);
          await file.writeAsBytes(bytes);
        } catch (_) {}
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) => other is _CachedTileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
