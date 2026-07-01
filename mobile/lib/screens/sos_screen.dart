import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';

/// Emergency SOS — hold to send an offline alert with location + type.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _mesh = MeshService.instance;
  String _type = 'Emergency';
  static const _types = ['Emergency', 'Medical', 'Fire', 'Flood', 'Rescue'];

  @override
  void initState() {
    super.initState();
    _mesh.start();
  }

  Future<void> _sendSos() async {
    await _mesh.sendSOS(_type);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Brand.coral,
        content: Text('SOS sent — broadcasting to your barangay',
            style: TextStyle(color: Colors.white)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS')),
      body: AnimatedBuilder(
        animation: _mesh,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Text('Hold the button to send an SOS',
                textAlign: TextAlign.center, style: TextStyle(color: Brand.textDim)),
            const SizedBox(height: 20),
            Center(child: _HoldSos(onSend: _sendSos)),
            const SizedBox(height: 20),
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
                  selectedColor: Brand.coral.withValues(alpha: 0.18),
                  backgroundColor: Brand.surface,
                  labelStyle: TextStyle(
                      color: sel ? Brand.coral : Brand.textDim,
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                  side: BorderSide(color: sel ? Brand.coral : Brand.line),
                  onSelected: (_) => setState(() => _type = t),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            const Text('Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_mesh.alerts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No emergencies — everyone\'s okay. 🪺',
                    style: TextStyle(color: Brand.textDim)),
              )
            else
              ..._mesh.alerts.map(_alertTile),
          ],
        ),
      ),
    );
  }

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
            Text(
              '${a.type}${a.medical.isNotEmpty ? ' · ${a.medical}' : ''}'
              '${a.hasLocation ? ' · 📍 ${a.lat!.toStringAsFixed(3)}, ${a.lng!.toStringAsFixed(3)}' : ' · no GPS'}',
              style: const TextStyle(color: Brand.textDim, fontSize: 12),
            ),
            if (mine)
              const Text('waiting for help…', style: TextStyle(color: Brand.textDim, fontSize: 11)),
          ]),
        ),
      ]),
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
          width: 200,
          height: 200,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 200,
              height: 200,
              child: CircularProgressIndicator(
                value: _c.value == 0 ? null : _c.value,
                strokeWidth: 6,
                color: Brand.coral,
                backgroundColor: Brand.coral.withValues(alpha: 0.15),
              ),
            ),
            Container(
              width: 166,
              height: 166,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.coral,
                boxShadow: [BoxShadow(color: Brand.coral.withValues(alpha: 0.4), blurRadius: 30)],
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
