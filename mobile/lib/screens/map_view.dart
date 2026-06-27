import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../mock_data.dart';
import '../services/mesh_service.dart';
import '../services/offline_tiles.dart';

/// Online Nest Mat — a real OpenStreetMap with family GPS pins.
/// Defaults to the Philippines (Manila) until a live location is resolved.
class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const _manila = LatLng(14.5995, 120.9842);
  final _controller = MapController();
  LatLng _center = _manila;
  LatLng? _me;
  String _note = 'Locating…';
  Directory? _tileDir;

  @override
  void initState() {
    super.initState();
    _locate();
    TileCache.instance.ensureDir().then((d) {
      if (mounted) setState(() => _tileDir = d);
    });
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _note = 'Location off · showing Philippines');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _note = 'No location permission · showing Philippines');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final here = LatLng(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() {
        _me = here;
        _center = here;
        _note = 'Live GPS';
      });
      _controller.move(here, 15);
    } catch (_) {
      if (mounted) setState(() => _note = 'Location unavailable · showing Philippines');
    }
  }

  /// Mock family positions offset around the centre (real positions arrive
  /// via the loc envelope / Firebase in a later sprint).
  LatLng _memberPos(FamilyMember m) {
    final base = _me ?? _center;
    final dDeg = m.distanceM / 111000.0;
    return LatLng(
      base.latitude + dDeg * math.cos(m.bearing),
      base.longitude + dDeg * math.sin(m.bearing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final others = family.where((m) => m.id != meId).toList();
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(initialCenter: _center, initialZoom: 14),
          children: [
            TileLayer(
              urlTemplate: tileUrlTemplate,
              userAgentPackageName: 'com.example.nest_link',
              tileProvider: _tileDir != null ? CachedTileProvider(_tileDir!) : null,
            ),
            AnimatedBuilder(
              animation: MeshService.instance,
              builder: (context, _) {
                final meshWithGps = MeshService.instance.presence
                    .where((p) => p.hasLocation)
                    .toList();
                final markers = <Marker>[
                  if (_me != null) _marker(_me!, 'You', Brand.emerald, isMe: true),
                ];
                if (meshWithGps.isNotEmpty) {
                  // Real family positions shared over the mesh.
                  for (final p in meshWithGps) {
                    markers.add(_marker(LatLng(p.lat!, p.lng!), p.name, _colorFor(p.eid)));
                  }
                } else {
                  // No live positions yet — show sample pins so the map isn't empty.
                  for (final m in others) {
                    markers.add(_marker(_memberPos(m), m.name, m.color));
                  }
                }
                return MarkerLayer(markers: markers);
              },
            ),
          ],
        ),
        Positioned(
          left: 12,
          top: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Brand.charcoal.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Brand.teal),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.gps_fixed, size: 14, color: Brand.teal),
              const SizedBox(width: 6),
              Text(_note, style: const TextStyle(fontSize: 12, color: Brand.text)),
            ]),
          ),
        ),
        const Positioned(
          right: 6,
          bottom: 4,
          child: Text('© OpenStreetMap, © CARTO',
              style: TextStyle(fontSize: 9, color: Brand.textDim)),
        ),
        Positioned(
          right: 12,
          bottom: 18,
          child: FloatingActionButton.extended(
            heroTag: 'saveArea',
            backgroundColor: Brand.surface,
            foregroundColor: Brand.emerald,
            onPressed: _tileDir == null ? null : _downloadArea,
            icon: const Icon(Icons.download_for_offline, size: 18),
            label: const Text('Save area', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

  /// Pre-download the current view (+1 zoom level) so it works offline.
  Future<void> _downloadArea() async {
    final cam = _controller.camera;
    final bounds = cam.visibleBounds;
    final zMin = cam.zoom.floor().clamp(3, 17);
    final zMax = (zMin + 1).clamp(3, 18);
    final total = TileCache.instance.countTiles(bounds, zMin, zMax);
    final progress = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Saving map for offline'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Downloading this area so the map works with no internet…',
                  style: TextStyle(color: Brand.textDim, fontSize: 13)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: total == 0 ? null : done / total,
                backgroundColor: Brand.charcoalHi,
                valueColor: const AlwaysStoppedAnimation(Brand.emerald),
              ),
              const SizedBox(height: 8),
              Text('$done / ${total > 1200 ? 1200 : total} tiles',
                  style: const TextStyle(color: Brand.textDim, fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    await TileCache.instance.downloadArea(bounds, zMin, zMax,
        onProgress: (done, _) => progress.value = done);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Saved! This area now works offline.'),
      duration: Duration(seconds: 2),
    ));
  }

  Color _colorFor(String eid) {
    const palette = [Brand.teal, Brand.amber, Brand.coral, Brand.emerald];
    return palette[eid.hashCode.abs() % palette.length];
  }

  Marker _marker(LatLng p, String label, Color color, {bool isMe = false}) {
    return Marker(
      point: p,
      width: 84,
      height: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Brand.charcoal.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
          ),
          Icon(isMe ? Icons.home : Icons.location_on, color: color, size: 30),
        ],
      ),
    );
  }
}
