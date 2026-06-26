import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Ensure the mesh is running whenever the family thread is open.
    _mesh.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keep the newest message in view (like a normal chat).
  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    await _mesh.sendChat(t);
    _controller.clear();
  }

  void _showFamilyCode() {
    final joinController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) {
          final code = _id.familyCode ?? '—';
          return AlertDialog(
            backgroundColor: Brand.surface,
            title: const Text('Family'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Your family code (share to invite):',
                    style: TextStyle(color: Brand.textDim, fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelectableText(code,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Brand.emerald,
                            letterSpacing: 2)),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Copied'), duration: Duration(seconds: 1)));
                      },
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Create a brand-new family
                OutlinedButton.icon(
                  onPressed: () async {
                    final newCode = await _id.createFamily();
                    await _mesh.syncFamilyCode();
                    setLocal(() {});
                    if (mounted) setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('New family created: $newCode'),
                        duration: const Duration(seconds: 2)));
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Brand.emerald)),
                  icon: const Icon(Icons.add_home, size: 18),
                  label: const Text('Create a new family'),
                ),
                const SizedBox(height: 12),

                // Join a different family
                TextField(
                  controller: joinController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Enter a code to join…',
                    isDense: true,
                    filled: true,
                    fillColor: Brand.charcoalHi,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    if (joinController.text.trim().isEmpty) return;
                    await _id.joinFamily(joinController.text);
                    await _mesh.syncFamilyCode();
                    setLocal(() {});
                    if (mounted) setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Joined family ${_id.familyCode}'),
                        duration: const Duration(seconds: 2)));
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: Brand.teal, foregroundColor: Brand.charcoal),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Join with code'),
                ),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
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
          IconButton(
            tooltip: 'Family code',
            icon: const Icon(Icons.group, size: 20),
            onPressed: _showFamilyCode,
          ),
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
          _connectedBar(),
          Expanded(
            child: AnimatedBuilder(
              animation: _mesh,
              builder: (context, _) {
                final msgs = _mesh.messages;
                if (msgs.isEmpty) return _empty();
                _jumpToBottom(); // stick to the newest message
                return ListView.builder(
                  controller: _scroll,
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

  Widget _connectedBar() {
    return AnimatedBuilder(
      animation: _mesh,
      builder: (context, _) {
        final live = _mesh.presence;
        final names = live
            .map((p) => _id.isKnown(p.eid) ? _id.nameForEid(p.eid) : p.name)
            .toList();
        final hasFamily = names.isNotEmpty;
        return Container(
          width: double.infinity,
          color: hasFamily ? Brand.emeraldDim.withValues(alpha: 0.25) : Brand.surface,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Icon(hasFamily ? Icons.group : Icons.search,
                  size: 15, color: hasFamily ? Brand.emerald : Brand.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasFamily
                      ? 'Connected: ${names.join(", ")}'
                      : (_mesh.running
                          ? 'Searching for family nearby…'
                          : 'Mesh off'),
                  style: TextStyle(
                      fontSize: 12.5,
                      color: hasFamily ? Brand.emerald : Brand.textDim,
                      fontWeight: hasFamily ? FontWeight.w600 : FontWeight.normal),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasFamily)
                Text('${names.length} nearby',
                    style: const TextStyle(fontSize: 11, color: Brand.textDim)),
            ],
          ),
        );
      },
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
