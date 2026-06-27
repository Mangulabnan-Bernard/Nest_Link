import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';

/// A real 1-on-1 private chat with a single family member (unicast over mesh).
class PrivateChatScreen extends StatefulWidget {
  final String peerEid;
  final String peerName;
  const PrivateChatScreen({super.key, required this.peerEid, required this.peerName});

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    await _mesh.sendChatTo(widget.peerEid, t);
    _controller.clear();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String get _name => _id.isKnown(widget.peerEid) ? _id.nameForEid(widget.peerEid) : widget.peerName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Brand.surfaceHi,
              child: Text(
                _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_name),
                const Text('private · only you two',
                    style: TextStyle(fontSize: 11, color: Brand.textDim, fontWeight: FontWeight.normal)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _mesh,
              builder: (context, _) {
                final msgs = _mesh.directMessagesWith(widget.peerEid);
                if (msgs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Private chat with $_name.\nMessages here go only to them.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Brand.textDim),
                      ),
                    ),
                  );
                }
                _jumpToBottom();
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

  Widget _bubble(MeshMessage m) {
    final mine = m.sourceEid == 'me';
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.text, style: const TextStyle(color: Brand.text)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (m.viaMesh) ...[
                const Icon(Icons.hub, size: 11, color: Colors.white),
                const SizedBox(width: 2),
                Text('mesh · ${m.hopCount} hops',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
              ] else
                const Text('sent', style: TextStyle(color: Colors.white70, fontSize: 9)),
            ]),
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
                decoration: InputDecoration(
                  hintText: 'Message $_name…',
                  filled: true,
                  fillColor: Brand.surface,
                  isDense: true,
                  border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)), borderSide: BorderSide.none),
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
