import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/mesh_service.dart';
import '../services/identity.dart';
import 'family_nest_screen.dart';
import 'private_chat_screen.dart';

/// Chirp Chat — the Family Nest group thread plus a live list of nearby family
/// you can message privately (1-on-1).
class ChirpChatScreen extends StatefulWidget {
  const ChirpChatScreen({super.key});

  @override
  State<ChirpChatScreen> createState() => _ChirpChatScreenState();
}

class _ChirpChatScreenState extends State<ChirpChatScreen> {
  final _mesh = MeshService.instance;
  final _id = Identity.instance;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _mesh.start(); // so nearby family appears even before opening a thread
  }

  String _nameFor(MemberPresence p) => _id.isKnown(p.eid) ? _id.nameForEid(p.eid) : p.name;

  Future<void> _searchNearby() async {
    setState(() => _searching = true);
    await _mesh.rescan();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Searching for family nearby…'), duration: Duration(seconds: 2)));
    }
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chirp Chat')),
      body: AnimatedBuilder(
        animation: _mesh,
        builder: (context, _) {
          final family = _mesh.familyReachable;
          final others = _mesh.othersReachable;
          return ListView(
            children: [
              // Group thread
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const CircleAvatar(
                  radius: 26,
                  backgroundColor: Brand.surfaceHi,
                  child: Icon(Icons.diversity_3, color: Brand.emerald),
                ),
                title: Row(children: [
                  const Text('Family Nest', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  _liveChip(),
                ]),
                subtitle: const Text('Group · everyone in your family',
                    style: TextStyle(color: Brand.textDim)),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FamilyNestScreen())),
              ),
              const Divider(height: 1, indent: 76),

              // Your family (private chats)
              _sectionHeader('Your family', family.length, withSearch: true),
              if (family.isEmpty)
                _emptyHint(
                    'No family nearby yet.\nShare your family code so they can join,\nor tap "Search".')
              else
                ...family.map(_personTile),

              // Others nearby (open discovery — tap to chat privately)
              if (others.isNotEmpty) ...[
                _sectionHeader('Others nearby', others.length),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('People nearby using the app — tap to chat them privately.',
                      style: TextStyle(color: Brand.textDim, fontSize: 11)),
                ),
                ...others.map(_personTile),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _liveChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: Brand.emerald.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
        child: const Text('LIVE',
            style: TextStyle(color: Brand.emerald, fontSize: 9, fontWeight: FontWeight.bold)),
      );

  Widget _sectionHeader(String title, int count, {bool withSearch = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(children: [
          Text(title,
              style: const TextStyle(
                  color: Brand.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Text('$count online', style: const TextStyle(color: Brand.textDim, fontSize: 12)),
          if (withSearch) ...[
            const Spacer(),
            if (_searching)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Row(children: [
                  SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Brand.emerald)),
                  SizedBox(width: 6),
                  Text('Searching…', style: TextStyle(color: Brand.emerald, fontSize: 12)),
                ]),
              )
            else
              TextButton.icon(
                onPressed: _searchNearby,
                icon: const Icon(Icons.radar, size: 16, color: Brand.emerald),
                label: const Text('Search', style: TextStyle(color: Brand.emerald, fontSize: 13)),
              ),
          ],
        ]),
      );

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.search, color: Brand.textDim, size: 36),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Brand.textDim)),
        ]),
      );

  Widget _personTile(MemberPresence p) {
    final strong = MeshService.qualityOf(p) == 'strong';
    final name = _nameFor(p);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Brand.surfaceHi,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: strong ? Brand.emerald : Brand.amber,
              shape: BoxShape.circle,
              border: Border.all(color: Brand.charcoal, width: 2),
            ),
          ),
        ),
      ]),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(strong ? 'on mesh · strong signal' : 'on mesh · weak signal',
          style: const TextStyle(color: Brand.textDim, fontSize: 12)),
      trailing: const Icon(Icons.lock_outline, size: 16, color: Brand.textDim),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PrivateChatScreen(peerEid: p.eid, peerName: name)),
      ),
    );
  }
}
