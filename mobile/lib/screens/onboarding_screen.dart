import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../services/identity.dart';

/// First-run flow: who you are, then create or join a family.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0 = profile, 1 = family
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String _role = 'parent';

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_nameController.text.trim().isEmpty) return;
    await Identity.instance.setProfile(_nameController.text.trim(), _role);
    setState(() => _step = 1);
  }

  Future<void> _createFamily() async {
    final code = await Identity.instance.createFamily();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('Your family code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with your family so they can join:',
                style: TextStyle(color: Brand.textDim)),
            const SizedBox(height: 16),
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold, color: Brand.emerald, letterSpacing: 2)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDone();
            },
            child: const Text('Enter the Nest'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinFamily() async {
    if (_codeController.text.trim().isEmpty) return;
    await Identity.instance.joinFamily(_codeController.text);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == 0 ? _profileStep() : _familyStep(),
        ),
      ),
    );
  }

  Widget _profileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        const Center(child: Text('🪺', style: TextStyle(fontSize: 64))),
        const SizedBox(height: 16),
        const Text('Welcome to Nest Link',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Let your family know who you are.',
            textAlign: TextAlign.center, style: TextStyle(color: Brand.textDim)),
        const SizedBox(height: 32),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'e.g. Tatay, Kuya, Ate…',
            filled: true,
            fillColor: Brand.surface,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _next(),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'parent', label: Text('Parent'), icon: Icon(Icons.shield)),
            ButtonSegment(value: 'child', label: Text('Child'), icon: Icon(Icons.child_care)),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        const Spacer(),
        FilledButton(
          onPressed: _next,
          style: FilledButton.styleFrom(
            backgroundColor: Brand.emerald,
            foregroundColor: Brand.charcoal,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _familyStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
          ),
        ),
        const Spacer(),
        const Center(child: Text('👨‍👩‍👧‍👦', style: TextStyle(fontSize: 56))),
        const SizedBox(height: 16),
        const Text('Your family nest',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Only members with the same code can see each other.',
            textAlign: TextAlign.center, style: TextStyle(color: Brand.textDim)),
        const SizedBox(height: 32),

        // Create new
        FilledButton.icon(
          onPressed: _createFamily,
          style: FilledButton.styleFrom(
            backgroundColor: Brand.emerald,
            foregroundColor: Brand.charcoal,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.add_home),
          label: const Text('Create a new family', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            Expanded(child: Divider(color: Brand.line)),
            Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or', style: TextStyle(color: Brand.textDim))),
            Expanded(child: Divider(color: Brand.line)),
          ]),
        ),

        // Join existing
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Family code',
            hintText: 'e.g. NEST-7XK2',
            prefixIcon: Icon(Icons.group_add),
            filled: true,
            fillColor: Brand.surface,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _joinFamily(),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _joinFamily,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Brand.teal),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Join with code'),
        ),
        const Spacer(),
      ],
    );
  }
}
