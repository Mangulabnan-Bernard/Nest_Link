import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';

/// The real Family Nest broadcast thread — live over the dtn-mesh engine.
class FamilyNestScreen extends StatefulWidget {
  const FamilyNestScreen({super.key});

  @override
  State<FamilyNestScreen> createState() => _FamilyNestScreenState();
}

class _FamilyNestScreenState extends State<FamilyNestScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ensure the mesh is running whenever the family thread is open.
    _mesh.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    await _mesh.sendChat(t);
    _controller.clear();
  }

  Future<void> _renameSender(String eid) async {
    final ctrl = TextEditingController(text: _id.nameForEid(eid));
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Name this nestling'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Kuya'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _id.rename(eid, name.trim());
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Brand.surfaceHi,
              child: Icon(Icons.diversity_3, size: 18, color: Brand.emerald),
            ),
            const SizedBox(width: 10),
            const Text('Family Nest'),
          ],
        ),
        actions: [
          AnimatedBuilder(
            animation: _mesh,
            builder: (_, _) {
              final connecting = _mesh.running && _mesh.eid == null;
              final label = !_mesh.running ? 'off' : (connecting ? 'connecting…' : 'live');
              final color = !_mesh.running
                  ? Brand.textDim
                  : (connecting ? Brand.amber : Brand.emerald);
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Row(
                  children: [
                    if (connecting)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Brand.amber),
                      )
                    else
                      Icon(Icons.hub, size: 14, color: color),
                    const SizedBox(width: 5),
                    Text(label, style: TextStyle(fontSize: 12, color: color)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _mesh,
              builder: (context, _) {
                final msgs = _mesh.messages;
                if (msgs.isEmpty) return _empty();
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: msgs.length,
                  itemBuilder: (context, i) => _bubble(msgs[i]),
                );
              },
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub, size: 48, color: Brand.emeraldDim),
            const SizedBox(height: 12),
            Text(
              _mesh.running
                  ? 'Mesh is live. Send the first chirp —\nfamily nearby will receive it offline.'
                  : 'Starting the mesh…',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.textDim),
            ),
            if (_mesh.eid != null) ...[
              const SizedBox(height: 8),
              Text('You are ${_id.name} · ${_mesh.eid}',
                  style: const TextStyle(color: Brand.textDim, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bubble(MeshMessage m) {
    final mine = m.sourceEid == 'me';
    final senderName = mine ? null : m.senderName;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          gradient: m.viaMesh ? Brand.meshGradient : null,
          color: m.viaMesh ? null : (mine ? Brand.teal : Brand.surface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          boxShadow: m.viaMesh
              ? [BoxShadow(color: Brand.emerald.withValues(alpha: 0.35), blurRadius: 12)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (senderName != null)
              GestureDetector(
                onTap: () => _renameSender(m.sourceEid),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(senderName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                    if (!_id.isKnown(m.sourceEid)) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 11, color: Colors.white70),
                    ],
                  ],
                ),
              ),
            Text(m.text, style: const TextStyle(color: Brand.text)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (m.viaMesh) ...[
                  const Icon(Icons.hub, size: 11, color: Colors.white),
                  const SizedBox(width: 2),
                  Text('mesh · ${m.hopCount} hops',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                ] else
                  const Text('sent',
                      style: TextStyle(color: Colors.white70, fontSize: 9)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: Brand.charcoalHi,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Send a chirp to the family…',
                  filled: true,
                  fillColor: Brand.surface,
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                      borderSide: BorderSide.none),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Brand.emerald,
              child: IconButton(
                icon: const Icon(Icons.send, color: Brand.charcoal),
                onPressed: _send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
