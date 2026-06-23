import 'package:flutter/material.dart';
import '../theme.dart';
import '../mock_data.dart';
import '../services/mesh_service.dart';

/// Safe Flight — one-tap status check-ins + shared family checklist.
class SafeFlightScreen extends StatefulWidget {
  const SafeFlightScreen({super.key});

  @override
  State<SafeFlightScreen> createState() => _SafeFlightScreenState();
}

class _SafeFlightScreenState extends State<SafeFlightScreen> {
  final _mesh = MeshService.instance;
  String _myStatus = "I'm Safe";
  late final List<ChecklistItem> _items = List.of(checklist);

  @override
  void initState() {
    super.initState();
    _mesh.start(); // ensure the mesh is up so status check-ins broadcast
  }

  void _pickStatus(String label) {
    setState(() => _myStatus = label);
    _mesh.sendStatus(label);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Status shared with the family: $label'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final others = family.where((m) => m.id != meId).toList();
    final done = _items.where((i) => i.checked).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Safe Flight')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('My status'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: statusOptions.map((o) {
              final sel = o.label == _myStatus;
              return GestureDetector(
                onTap: () => _pickStatus(o.label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? o.color.withValues(alpha: 0.18) : Brand.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: sel ? o.color : Brand.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(o.icon, size: 16, color: sel ? o.color : Brand.textDim),
                      const SizedBox(width: 6),
                      Text(o.label,
                          style: TextStyle(
                              color: sel ? o.color : Brand.textDim,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _mesh,
            builder: (context, _) {
              final live = _mesh.presence;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _sectionTitle('Family'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: (live.isEmpty ? Brand.textDim : Brand.emerald)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(live.isEmpty ? 'SAMPLE' : 'LIVE',
                            style: TextStyle(
                                color: live.isEmpty ? Brand.textDim : Brand.emerald,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (live.isEmpty)
                    ...others.map(_familyCard)
                  else
                    ...live.map(_presenceCard),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _sectionTitle('Survival checklist'),
              const Spacer(),
              Text('$done / ${_items.length}',
                  style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: done / _items.length,
              minHeight: 6,
              backgroundColor: Brand.surface,
              valueColor: const AlwaysStoppedAnimation(Brand.emerald),
            ),
          ),
          const SizedBox(height: 12),
          ..._items.asMap().entries.map((e) => _checkItem(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String s) => Text(s,
      style: const TextStyle(
          color: Brand.text, fontSize: 16, fontWeight: FontWeight.w700));

  StatusOption _statusFor(String label) =>
      statusOptions.firstWhere((o) => o.label == label,
          orElse: () => statusOptions.first);

  Widget _familyCard(FamilyMember m) {
    final s = _statusFor(m.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  backgroundColor: m.color.withValues(alpha: 0.2),
                  child: Text(m.initials,
                      style: TextStyle(
                          color: m.color, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: m.online ? Brand.emerald : Brand.textDim,
                      shape: BoxShape.circle,
                      border: Border.all(color: Brand.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(m.lastSeen, style: const TextStyle(color: Brand.textDim, fontSize: 11)),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, size: 14, color: s.color),
                  const SizedBox(width: 5),
                  Text(m.status,
                      style: TextStyle(
                          color: s.color, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _colorFor(String eid) {
    const palette = [Brand.teal, Brand.amber, Brand.coral, Brand.emerald];
    return palette[eid.hashCode.abs() % palette.length];
  }

  String _initialsFor(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return t.length >= 2 ? t.substring(0, 2).toUpperCase() : t.toUpperCase();
  }

  String _ago(int ms) {
    final secs = (DateTime.now().millisecondsSinceEpoch - ms) ~/ 1000;
    if (secs < 60) return '${secs}s ago';
    if (secs < 3600) return '${secs ~/ 60}m ago';
    return '${secs ~/ 3600}h ago';
  }

  Widget _presenceCard(MemberPresence p) {
    final color = _colorFor(p.eid);
    final online = DateTime.now().millisecondsSinceEpoch - p.lastSeenMs < 90000;
    final s = _statusFor(p.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Text(_initialsFor(p.name),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: online ? Brand.emerald : Brand.textDim,
                      shape: BoxShape.circle,
                      border: Border.all(color: Brand.surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  const Icon(Icons.hub, size: 11, color: Brand.emerald),
                  const SizedBox(width: 3),
                  Text('on mesh · ${_ago(p.lastSeenMs)}',
                      style: const TextStyle(color: Brand.textDim, fontSize: 11)),
                ]),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, size: 14, color: s.color),
                  const SizedBox(width: 5),
                  Text(p.status,
                      style: TextStyle(color: s.color, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(int index, ChecklistItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: item.checked,
        onChanged: (v) => setState(
            () => _items[index] = ChecklistItem(item.text, v ?? false, item.by)),
        activeColor: Brand.emerald,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(item.text,
            style: TextStyle(
                decoration: item.checked ? TextDecoration.lineThrough : null,
                color: item.checked ? Brand.textDim : Brand.text)),
        subtitle: Text('added by ${item.by}',
            style: const TextStyle(color: Brand.textDim, fontSize: 11)),
      ),
    );
  }
}
