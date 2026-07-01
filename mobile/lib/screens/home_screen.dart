import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';

/// Home command center — SOS front-and-center, plus alerts + family at a glance.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  String _type = 'Emergency';
  static const _types = ['Emergency', 'Medical', 'Fire', 'Flood', 'Rescue'];
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

  /// Pop a loud banner the moment a new incoming SOS arrives.
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
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ));
    }
  }

  Future<void> _sendSos() async {
    await _mesh.sendSOS(_type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Brand.coral,
        content: Text('SOS sent — broadcasting to your family/barangay'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('🪺 '),
          const Text('Nest Link'),
          const Spacer(),
          Text(_id.name ?? '',
              style: const TextStyle(color: Brand.textDim, fontSize: 13, fontWeight: FontWeight.normal)),
        ]),
      ),
      body: AnimatedBuilder(
        animation: _mesh,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            children: [
              Center(child: _HoldSos(onSend: _sendSos)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _types.map((t) {
                  final sel = t == _type;
                  return ChoiceChip(
                    label: Text(t),
                    selected: sel,
                    showCheckmark: false,
                    selectedColor: Brand.coral.withValues(alpha: 0.25),
                    backgroundColor: Brand.surface,
                    labelStyle: TextStyle(color: sel ? Brand.coral : Brand.textDim, fontSize: 13),
                    side: BorderSide(color: sel ? Brand.coral : Brand.line),
                    onSelected: (_) => setState(() => _type = t),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              _sectionTitle('Alerts', _mesh.alerts.length),
              const SizedBox(height: 8),
              if (_mesh.alerts.isEmpty)
                _hint('No emergencies. Everyone\'s okay. 🪺')
              else
                ..._mesh.alerts.map(_alertCard),
              const SizedBox(height: 28),
              _sectionTitle('Family nearby', _mesh.familyReachable.length),
              const SizedBox(height: 8),
              if (_mesh.familyReachable.isEmpty)
                _hint('No family on the mesh yet.')
              else
                ..._mesh.familyReachable.map(_familyRow),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String s, int count) => Row(children: [
        Text(s, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: const TextStyle(color: Brand.textDim, fontSize: 12)),
          ),
      ]);

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(s, style: const TextStyle(color: Brand.textDim)),
      );

  Widget _alertCard(SosAlert a) {
    final mine = a.mine;
    return Card(
      color: mine ? Brand.surface : Brand.coral.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: mine ? Brand.line : Brand.coral),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Icon(mine ? Icons.upload : Icons.sos, color: Brand.coral, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mine ? 'You sent an SOS' : '${a.name} needs help',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                '${a.type}${a.medical.isNotEmpty ? ' · ${a.medical}' : ''}'
                '${a.hasLocation ? ' · 📍 ${a.lat!.toStringAsFixed(4)}, ${a.lng!.toStringAsFixed(4)}' : ' · no GPS'}',
                style: const TextStyle(color: Brand.textDim, fontSize: 12.5),
              ),
              if (mine)
                const Text('waiting for help…', style: TextStyle(color: Brand.textDim, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _familyRow(MemberPresence p) {
    final strong = MeshService.qualityOf(p) == 'strong';
    final name = _id.isKnown(p.eid) ? _id.nameForEid(p.eid) : p.name;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: Brand.surfaceHi,
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(p.status == '—' ? 'on mesh' : p.status,
          style: const TextStyle(color: Brand.textDim, fontSize: 12)),
      trailing: Icon(strong ? Icons.wifi : Icons.network_wifi_1_bar,
          size: 16, color: strong ? Brand.emerald : Brand.amber),
    );
  }
}

/// Big hold-to-send SOS button (prevents accidental triggers).
class _HoldSos extends StatefulWidget {
  final Future<void> Function() onSend;
  const _HoldSos({required this.onSend});

  @override
  State<_HoldSos> createState() => _HoldSosState();
}

class _HoldSosState extends State<_HoldSos> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _fire();
        });
  bool _sending = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _start() {
    if (!_sending) _c.forward(from: 0);
  }

  void _cancel() {
    if (!_sending && !_c.isCompleted) _c.reset();
  }

  Future<void> _fire() async {
    setState(() => _sending = true);
    await widget.onSend();
    if (mounted) setState(() => _sending = false);
    _c.reset();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _cancel(),
      onTapCancel: _cancel,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => SizedBox(
          width: 210,
          height: 210,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 210,
              height: 210,
              child: CircularProgressIndicator(
                value: _c.value == 0 ? null : _c.value,
                strokeWidth: 7,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            Container(
              width: 176,
              height: 176,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.coral,
                boxShadow: [BoxShadow(color: Brand.coral.withValues(alpha: 0.5), blurRadius: 34)],
              ),
              child: Center(
                child: _sending
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('SOS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 46,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2)),
                        SizedBox(height: 2),
                        Text('hold to send', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
