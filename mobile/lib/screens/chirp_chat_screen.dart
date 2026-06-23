import 'package:flutter/material.dart';
import '../theme.dart';
import '../mock_data.dart';
import 'family_nest_screen.dart';

/// Chirp Chat — family-first messaging. Mesh-delivered chirps glimmer emerald
/// with a nest icon.
class ChirpChatScreen extends StatelessWidget {
  const ChirpChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chirp Chat')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, i) {
          final c = conversations[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: Brand.surfaceHi,
              child: Icon(c.icon, color: Brand.emerald),
            ),
            title: Row(
              children: [
                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                if (c.id == 'fam')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                        color: Brand.emerald.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Brand.emerald, fontSize: 9, fontWeight: FontWeight.bold)),
                  )
                else if (c.lastViaMesh)
                  const Icon(Icons.hub, size: 14, color: Brand.emerald),
              ],
            ),
            subtitle: Text(c.id == 'fam' ? 'Real mesh · tap to chirp' : c.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Brand.textDim)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(c.time, style: const TextStyle(color: Brand.textDim, fontSize: 11)),
                const SizedBox(height: 6),
                if (c.unread > 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                        color: Brand.emerald, shape: BoxShape.circle),
                    child: Text('${c.unread}',
                        style: const TextStyle(
                            color: Brand.charcoal,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => c.id == 'fam'
                    ? const FamilyNestScreen()
                    : ChatThreadScreen(conversation: c),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChatThreadScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatThreadScreen({super.key, required this.conversation});

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  late final List<ChirpMessage> _messages =
      List.of(widget.conversation.messages);
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _messages.add(ChirpMessage(fromId: meId, text: t, time: 'now'));
      _controller.clear();
    });
  }

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
              child: Icon(widget.conversation.icon, size: 18, color: Brand.emerald),
            ),
            const SizedBox(width: 10),
            Text(widget.conversation.title),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _bubble(_messages[i]),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(ChirpMessage m) {
    final mine = m.fromId == meId;
    final sender = mine ? null : memberById(m.fromId);
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
            if (sender != null)
              Text(sender.name,
                  style: TextStyle(
                      color: sender.color, fontSize: 11, fontWeight: FontWeight.bold)),
            if (m.isVoice) _voice(m) else Text(m.text, style: const TextStyle(color: Brand.text)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.time,
                    style: TextStyle(
                        color: mine || m.viaMesh
                            ? Colors.white70
                            : Brand.textDim,
                        fontSize: 10)),
                if (m.viaMesh) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.hub, size: 11, color: Colors.white),
                  const SizedBox(width: 2),
                  const Text('mesh',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _voice(ChirpMessage m) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_fill, color: Colors.white, size: 28),
        const SizedBox(width: 8),
        Container(width: 90, height: 3, color: Colors.white54),
        const SizedBox(width: 8),
        Text('0:0${m.voiceSeconds}', style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
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
            const Icon(Icons.mic, color: Brand.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  hintText: 'Send a chirp…',
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
