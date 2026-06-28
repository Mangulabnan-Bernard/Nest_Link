import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';
import '../services/voice.dart';

/// The real Family Nest broadcast thread — live over the dtn-mesh engine.
class FamilyNestScreen extends StatefulWidget {
  const FamilyNestScreen({super.key});

  @override
  State<FamilyNestScreen> createState() => _FamilyNestScreenState();
}

class _FamilyNestScreenState extends State<FamilyNestScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  final _voice = Voice.instance;
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  Set<String> _prevReachable = {};
  bool _baselineSet = false;
  bool _recording = false;

  Future<void> _startRecord() async {
    final ok = await _voice.start();
    if (!ok) {
      _toast('Microphone permission needed', Brand.coral, Icons.mic_off);
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _stopAndSendVoice() async {
    setState(() => _recording = false);
    final b64 = await _voice.stopAsBase64();
    if (b64 == null) {
      if (mounted) _toast('Keep the voice clip short (a few seconds)', Brand.amber, Icons.mic_off);
      return;
    }
    await _mesh.sendVoice(b64);
  }

  Future<void> _cancelRecord() async {
    setState(() => _recording = false);
    await _voice.cancel();
  }

  @override
  void initState() {
    super.initState();
    // Ensure the mesh is running whenever the family thread is open.
    _mesh.start();
    _mesh.addListener(_onMeshChange);
  }

  @override
  void dispose() {
    _mesh.removeListener(_onMeshChange);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _nameFor(String eid) {
    if (_id.isKnown(eid)) return _id.nameForEid(eid);
    final match = _mesh.presence.where((p) => p.eid == eid);
    return match.isNotEmpty ? match.first.name : 'A family member';
  }

  /// Toast when a family member connects or drops out of range.
  void _onMeshChange() {
    if (!mounted) return;
    final now = _mesh.familyReachable.map((p) => p.eid).toSet();
    if (!_baselineSet) {
      _prevReachable = now;
      _baselineSet = true;
      return;
    }
    for (final eid in _prevReachable.difference(now)) {
      _toast('${_nameFor(eid)} went out of range', Brand.amber, Icons.signal_wifi_off);
    }
    for (final eid in now.difference(_prevReachable)) {
      _toast('${_nameFor(eid)} connected', Brand.emerald, Icons.wifi);
    }
    _prevReachable = now;
  }

  void _toast(String msg, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Brand.surfaceHi,
      duration: const Duration(seconds: 2),
      content: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(msg),
      ]),
    ));
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
                    if (!mounted) return;
                    setLocal(() {});
                    setState(() {});
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
                    if (!mounted) return;
                    setLocal(() {});
                    setState(() {});
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
                final msgs = _mesh.broadcastMessages;
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
        if (!_mesh.running) {
          return _bar(Brand.surface, Icons.hub, 'Mesh off', Brand.textDim);
        }
        final members = _mesh.familyReachable;
        if (members.isEmpty) {
          return _bar(Brand.surface, Icons.search, 'Searching for family nearby…', Brand.textDim);
        }
        final weak = members.where((p) => MeshService.qualityOf(p) == 'weak').toList();
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: Brand.emeraldDim.withValues(alpha: 0.22),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.group, size: 15, color: Brand.emerald),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: members.map((p) {
                        final strong = MeshService.qualityOf(p) == 'strong';
                        final c = strong ? Brand.emerald : Brand.amber;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(strong ? Icons.wifi : Icons.network_wifi_1_bar, size: 13, color: c),
                            const SizedBox(width: 4),
                            Text(_nameFor(p.eid),
                                style: const TextStyle(
                                    color: Brand.text, fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  Text('${members.length} nearby',
                      style: const TextStyle(fontSize: 11, color: Brand.textDim)),
                ],
              ),
            ),
            for (final p in weak)
              Container(
                width: double.infinity,
                color: Brand.amber.withValues(alpha: 0.14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(children: [
                  const Icon(Icons.warning_amber, size: 14, color: Brand.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${_nameFor(p.eid)}\'s signal is weak — may be moving away',
                        style: const TextStyle(color: Brand.amber, fontSize: 11.5)),
                  ),
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _bar(Color bg, IconData icon, String text, Color fg) => Container(
        width: double.infinity,
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12.5, color: fg)),
        ]),
      );

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
            if (m.isVoice) _voiceContent(m) else Text(m.text, style: const TextStyle(color: Brand.text)),
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

  Future<void> _playVoice(MeshMessage m) async {
    final err = await _voice.play(m.audioB64!);
    if (err != null && mounted) _toast('Could not play voice clip', Brand.coral, Icons.volume_off);
  }

  Widget _voiceContent(MeshMessage m) {
    final canPlay = m.audioB64 != null;
    return InkWell(
      onTap: canPlay ? () => _playVoice(m) : null,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(canPlay ? Icons.play_circle_fill : Icons.mic,
            color: canPlay ? Brand.text : Brand.textDim, size: 26),
        const SizedBox(width: 8),
        Text(canPlay ? 'Voice message · tap to play' : 'Voice message',
            style: const TextStyle(color: Brand.text)),
      ]),
    );
  }

  Widget _composer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
      color: Brand.charcoalHi,
      child: SafeArea(
        top: false,
        child: _recording
            ? Row(children: [
                const SizedBox(width: 8),
                const Icon(Icons.fiber_manual_record, color: Brand.coral, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Recording… send or cancel', style: TextStyle(color: Brand.coral))),
                TextButton(onPressed: _cancelRecord, child: const Text('Cancel')),
                const SizedBox(width: 4),
                CircleAvatar(
                  backgroundColor: Brand.emerald,
                  child: IconButton(
                      icon: const Icon(Icons.send, color: Brand.charcoal), onPressed: _stopAndSendVoice),
                ),
              ])
            : Row(children: [
                IconButton(
                    icon: const Icon(Icons.mic, color: Brand.textDim), onPressed: _startRecord),
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
                      icon: const Icon(Icons.send, color: Brand.charcoal), onPressed: _send),
                ),
              ]),
      ),
    );
  }
}
