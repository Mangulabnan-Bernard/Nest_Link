import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/identity.dart';
import '../services/mesh_service.dart';
import 'mesh_test_screen.dart';

/// Me — profile, family code management, and diagnostics.
class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _id = Identity.instance;
  final _mesh = MeshService.instance;
  final _joinController = TextEditingController();

  @override
  void dispose() {
    _joinController.dispose();
    super.dispose();
  }

  Future<void> _createFamily() async {
    final code = await _id.createFamily();
    await _mesh.syncFamilyCode();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New family created: $code'), duration: const Duration(seconds: 2)));
  }

  Future<void> _joinFamily() async {
    if (_joinController.text.trim().isEmpty) return;
    await _id.joinFamily(_joinController.text);
    await _mesh.syncFamilyCode();
    if (!mounted) return;
    _joinController.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined ${_id.familyCode}'), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final code = _id.familyCode ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile
          Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Brand.emerald.withValues(alpha: 0.2),
              child: Text((_id.name ?? '?').isNotEmpty ? _id.name![0].toUpperCase() : '?',
                  style: const TextStyle(color: Brand.emerald, fontWeight: FontWeight.bold, fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_id.name ?? 'You',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              Text(_id.role == 'parent' ? 'Parent' : 'Child',
                  style: const TextStyle(color: Brand.textDim)),
            ]),
          ]),
          const SizedBox(height: 24),

          // Family code
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Your family / group code',
                    style: TextStyle(color: Brand.textDim, fontSize: 13)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: SelectableText(code,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold, color: Brand.emerald, letterSpacing: 2)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Copied'), duration: Duration(seconds: 1)));
                    },
                  ),
                ]),
                const Divider(height: 24),
                OutlinedButton.icon(
                  onPressed: _createFamily,
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Brand.emerald)),
                  icon: const Icon(Icons.add_home, size: 18),
                  label: const Text('Create a new family'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _joinController,
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
                  onPressed: _joinFamily,
                  style: FilledButton.styleFrom(
                      backgroundColor: Brand.teal, foregroundColor: Brand.charcoal),
                  icon: const Icon(Icons.group_add, size: 18),
                  label: const Text('Join with code'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Diagnostics
          Card(
            child: ListTile(
              leading: const Icon(Icons.monitor_heart, color: Brand.teal),
              title: const Text('Mesh diagnostics'),
              subtitle: const Text('Connection state + detected devices',
                  style: TextStyle(color: Brand.textDim, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Brand.textDim),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const MeshTestScreen())),
            ),
          ),
        ],
      ),
    );
  }
}
