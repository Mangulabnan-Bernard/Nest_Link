import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';

/// Live mesh tab — raw debug view of the dtn-mesh engine via [MeshService].
class MeshTestScreen extends StatefulWidget {
  const MeshTestScreen({super.key});

  @override
  State<MeshTestScreen> createState() => _MeshTestScreenState();
}

class _MeshTestScreenState extends State<MeshTestScreen> {
  final _mesh = MeshService.instance;
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    await _mesh.sendChat(text);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Mesh')),
      body: AnimatedBuilder(
        animation: _mesh,
        builder: (context, _) {
          final incoming = _mesh.messages.reversed.toList();
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statusCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: _mesh.running,
                        decoration: const InputDecoration(
                          hintText: 'Type a Chirp…',
                          filled: true,
                          fillColor: Brand.surface,
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: _mesh.running ? _send : null, child: const Text('Send')),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Messages (${incoming.length})',
                    style: const TextStyle(color: Brand.textDim, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Expanded(child: _list(incoming)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusCard() {
    final running = _mesh.running;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: running ? Brand.emerald : Brand.textDim, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub, color: running ? Brand.emerald : Brand.textDim),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(running
                      ? 'Mesh running — searching for family nearby'
                      : 'Mesh off')),
              Switch(
                value: running,
                activeThumbColor: Brand.emerald,
                onChanged: (v) => v ? _mesh.start() : _mesh.stop(),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Text('My EID:  ', style: TextStyle(color: Brand.textDim)),
              SelectableText(_mesh.eid ?? '—',
                  style: const TextStyle(color: Brand.emerald, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          // ── live radio diagnostic ──
          Row(children: [
            Icon(_mesh.wifiConnected ? Icons.wifi : Icons.wifi_find,
                size: 16, color: _mesh.wifiConnected ? Brand.emerald : Brand.amber),
            const SizedBox(width: 8),
            Text(
              _mesh.wifiConnected ? 'Wi-Fi link: CONNECTED' : 'Wi-Fi link: not connected yet',
              style: TextStyle(
                  color: _mesh.wifiConnected ? Brand.emerald : Brand.amber,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.devices_other, size: 16, color: Brand.textDim),
            const SizedBox(width: 8),
            Text('Devices seen nearby: ${_mesh.discoveredPeers}',
                style: const TextStyle(color: Brand.textDim, fontSize: 13)),
          ]),
          if (running && !_mesh.wifiConnected)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'If this stays "not connected": turn on Wi-Fi + Bluetooth + Location on both '
                'phones, disable battery optimization for Nest Link, keep both apps open, '
                'and accept the connection prompt.',
                style: TextStyle(color: Brand.textDim, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(List<MeshMessage> msgs) {
    if (msgs.isEmpty) {
      return const Center(
        child: Text('No messages yet.\nSend from another phone on the mesh.',
            textAlign: TextAlign.center, style: TextStyle(color: Brand.textDim)),
      );
    }
    return ListView.builder(
      itemCount: msgs.length,
      itemBuilder: (context, i) {
        final m = msgs[i];
        final mine = m.sourceEid == 'me';
        return Card(
          child: ListTile(
            leading: Icon(mine ? Icons.north_east : Icons.egg_alt,
                color: mine ? Brand.teal : Brand.emerald),
            title: Text(m.text.isEmpty ? '(message)' : m.text),
            subtitle: Text(
                mine
                    ? 'sent · broadcast'
                    : 'from ${m.senderName} · ${m.sourceEid} · hops ${m.hopCount}',
                style: const TextStyle(color: Brand.textDim, fontSize: 12)),
          ),
        );
      },
    );
  }
}
