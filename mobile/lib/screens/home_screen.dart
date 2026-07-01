import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';
import 'sos_screen.dart';

class _Service {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool soon;
  const _Service(this.icon, this.label, this.color, {this.onTap, this.soon = false});
}

/// Home — a barangay/community services hub: quick access to every feature,
/// with SOS one tap away and live safety info.
class HomeScreen extends StatefulWidget {
  final void Function(int tab)? onNavigate;
  const HomeScreen({super.key, this.onNavigate});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  String _query = '';
  String? _lastSeenSosId;

  @override
  void initState() {
    super.initState();
    _mesh.start();
    _mesh.addListener(_onChange);
  }

  @override
  void dispose() {
    _mesh.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    final incoming = _mesh.alerts.where((a) => !a.mine).toList();
    if (incoming.isNotEmpty && incoming.first.id != _lastSeenSosId) {
      _lastSeenSosId = incoming.first.id;
      final a = incoming.first;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Brand.coral,
        duration: const Duration(seconds: 5),
        content: Text('🆘 ${a.name} — ${a.type} — needs help!',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ));
    }
  }

  void _openSos() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SosScreen()));

  void _soon(String name) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$name — coming soon'), duration: const Duration(seconds: 1)));

  List<_Service> get _services => [
        _Service(Icons.emergency_share, 'Emergency', Brand.coral, onTap: _openSos),
        _Service(Icons.chat_bubble, 'Message', Brand.teal, onTap: () => widget.onNavigate?.call(1)),
        _Service(Icons.location_on, 'Map', Brand.amber, onTap: () => widget.onNavigate?.call(2)),
        _Service(Icons.verified_user, 'Check-in', Brand.emerald, onTap: () => widget.onNavigate?.call(3)),
        _Service(Icons.qr_code_2, 'QR ID', Brand.teal, soon: true),
        _Service(Icons.medical_services, 'Health', Brand.coral, soon: true),
        _Service(Icons.assignment, 'Reports', Brand.amber, soon: true),
        _Service(Icons.volunteer_activism, 'Ayuda', Brand.emerald, soon: true),
        _Service(Icons.menu_book, 'Guide', Brand.teal, soon: true),
        _Service(Icons.language, 'e-Services', Brand.amber, soon: true),
      ];

  @override
  Widget build(BuildContext context) {
    final services = _query.isEmpty
        ? _services
        : _services.where((s) => s.label.toLowerCase().contains(_query.toLowerCase())).toList();
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _mesh,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _greeting(),
              const SizedBox(height: 14),
              _search(),
              const SizedBox(height: 10),
              _statusBar(),
              const SizedBox(height: 22),
              Row(children: [
                const Text('Essential Services',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_query.isNotEmpty)
                  Text('${services.length} found', style: const TextStyle(color: Brand.textDim, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 8,
                childAspectRatio: 0.80,
                children: services.map(_serviceTile).toList(),
              ),
              const SizedBox(height: 20),
              _helpCard(),
              if (_mesh.alerts.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Active alerts',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ..._mesh.alerts.take(3).map(_alertTile),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _greeting() => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hi, ${_id.name ?? 'there'} 👋',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('What can we help you with today?',
                style: TextStyle(color: Brand.textDim)),
          ]),
        ),
        CircleAvatar(
          radius: 22,
          backgroundColor: Brand.emerald.withValues(alpha: 0.15),
          child: Text((_id.name ?? '?').isNotEmpty ? _id.name![0].toUpperCase() : '?',
              style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
      ]);

  Widget _search() => TextField(
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Search "Emergency", "QR ID", "Map"…',
          prefixIcon: const Icon(Icons.search, color: Brand.textDim),
          isDense: true,
          fillColor: Brand.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      );

  Widget _statusBar() {
    final connecting = _mesh.running && _mesh.eid == null;
    final ok = _mesh.running && !connecting;
    final label = !_mesh.running ? 'Mesh off' : (connecting ? 'Connecting…' : 'Mesh live · offline-ready');
    final c = !_mesh.running ? Brand.textDim : (connecting ? Brand.amber : Brand.emerald);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.line),
      ),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 13)),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.refresh, size: 18, color: Brand.textDim),
          onPressed: ok ? _mesh.rescan : _mesh.start,
        ),
      ]),
    );
  }

  Widget _serviceTile(_Service s) {
    return InkWell(
      onTap: s.soon ? () => _soon(s.label) : s.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(16)),
            child: Icon(s.icon, color: s.color, size: 26),
          ),
          if (s.soon)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration:
                    BoxDecoration(color: Brand.amber, borderRadius: BorderRadius.circular(6)),
                child: const Text('SOON',
                    style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold)),
              ),
            ),
        ]),
        const SizedBox(height: 7),
        Text(s.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _helpCard() => InkWell(
        onTap: _openSos,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFFF1F0), Color(0xFFFFE4E2)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Brand.coral.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.coral.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.emergency_share, color: Brand.coral, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Need immediate help?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('Tap to send an Emergency SOS',
                    style: TextStyle(color: Brand.textDim, fontSize: 12.5)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Brand.coral),
          ]),
        ),
      );

  Widget _alertTile(SosAlert a) {
    final mine = a.mine;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: mine ? Brand.surfaceHi : Brand.coral.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mine ? Brand.line : Brand.coral.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        Icon(mine ? Icons.upload : Icons.sos, color: Brand.coral, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine ? 'You sent an SOS' : '${a.name} needs help',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text('${a.type}${a.hasLocation ? ' · 📍 nearby' : ''}',
                style: const TextStyle(color: Brand.textDim, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}
