import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../mock_data.dart';
import '../services/mesh_service.dart';
import 'map_view.dart';

/// The Nest Mat — online GPS map / offline proximity radar.
class NestMatScreen extends StatefulWidget {
  const NestMatScreen({super.key});

  @override
  State<NestMatScreen> createState() => _NestMatScreenState();
}

class _NestMatScreenState extends State<NestMatScreen>
    with SingleTickerProviderStateMixin {
  final _mesh = MeshService.instance;
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  bool _offline = true; // demo starts in the eye-catching offline radar mode

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final others = family.where((m) => m.id != meId).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nest Mat'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _modeToggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _offline
                ? Center(
                    child: AnimatedBuilder(
                      animation: _sweep,
                      builder: (_, _) => CustomPaint(
                        size: const Size(320, 320),
                        painter: _RadarPainter(_sweep.value, others, online: !_offline),
                      ),
                    ),
                  )
                : const MapView(),
          ),
          _legend(),
          const SizedBox(height: 8),
          Expanded(
            child: AnimatedBuilder(
              animation: _mesh,
              builder: (context, _) {
                final live = _mesh.presence;
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: live.isEmpty
                      ? others.map(_memberTile).toList()
                      : live.map(_presenceTile).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _presenceTile(MemberPresence p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Brand.emerald.withValues(alpha: 0.2),
          child: const Icon(Icons.person, color: Brand.emerald, size: 18),
        ),
        title: Row(
          children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            const Icon(Icons.hub, size: 13, color: Brand.emerald),
          ],
        ),
        subtitle: Text('on mesh · ${p.status}',
            style: const TextStyle(color: Brand.textDim, fontSize: 12)),
        trailing: const Text('nearby',
            style: TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _modeToggle() {
    return GestureDetector(
      onTap: () => setState(() => _offline = !_offline),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _offline ? Brand.emerald : Brand.teal),
        ),
        child: Row(
          children: [
            Icon(_offline ? Icons.radar : Icons.map,
                size: 16, color: _offline ? Brand.emerald : Brand.teal),
            const SizedBox(width: 6),
            Text(_offline ? 'Radar · Offline' : 'Map · Online',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _offline ? Brand.emerald : Brand.teal)),
          ],
        ),
      ),
    );
  }

  Widget _legend() {
    return Text(
      _offline
          ? 'Offline mesh radar · distance via signal strength'
          : 'Online · live GPS positions',
      style: const TextStyle(color: Brand.textDim, fontSize: 12),
    );
  }

  Widget _memberTile(FamilyMember m) {
    final moving = m.id == 'kuya';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: m.color.withValues(alpha: 0.2),
          child: Text(m.initials,
              style: TextStyle(color: m.color, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        title: Row(
          children: [
            Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (m.viaMesh)
              const Icon(Icons.hub, size: 13, color: Brand.emerald)
            else
              const Icon(Icons.cloud_done, size: 13, color: Brand.teal),
          ],
        ),
        subtitle: Text(
          '${m.distanceM.toInt()}m away${moving ? ' · moving toward the Nest' : ''} · ${m.lastSeen}',
          style: const TextStyle(color: Brand.textDim, fontSize: 12),
        ),
        trailing: Text('${m.distanceM.toInt()}m',
            style: TextStyle(color: m.color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double sweep; // 0..1
  final List<FamilyMember> members;
  final bool online;
  _RadarPainter(this.sweep, this.members, {required this.online});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    final accent = online ? Brand.teal : Brand.emerald;

    // concentric rings
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.25);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxR * i / 4, ring);
    }
    // cross hairs
    final hair = Paint()..color = accent.withValues(alpha: 0.12)..strokeWidth = 1;
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), hair);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), hair);

    // rotating sweep wedge
    final sweepAngle = sweep * 2 * math.pi;
    final shader = SweepGradient(
      startAngle: sweepAngle,
      endAngle: sweepAngle + 0.8,
      colors: [accent.withValues(alpha: 0.0), accent.withValues(alpha: 0.28)],
    ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, Paint()..shader = shader);

    // home nest at center
    canvas.drawCircle(center, 22, Paint()..color = accent.withValues(alpha: 0.18));
    final tp = _label('🏠', 22);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    // members positioned by distance + bearing
    final maxDist = 360.0;
    for (final m in members) {
      final r = (m.distanceM / maxDist).clamp(0.12, 0.95) * maxR;
      final pos = center + Offset(math.cos(m.bearing) * r, math.sin(m.bearing) * r);
      // glow
      canvas.drawCircle(pos, 16, Paint()..color = m.color.withValues(alpha: 0.18));
      canvas.drawCircle(pos, 13, Paint()..color = Brand.charcoal);
      canvas.drawCircle(
          pos, 13, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = m.color);
      final mt = _label(m.initials, 10, color: m.color, bold: true);
      mt.paint(canvas, pos - Offset(mt.width / 2, mt.height / 2));
    }
  }

  TextPainter _label(String s, double size, {Color color = Brand.text, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              fontSize: size,
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.sweep != sweep || old.online != online;
}
