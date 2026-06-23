import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/identity.dart';

/// First-run screen: tell the family who you are.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  String _role = 'parent';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await Identity.instance.setProfile(name, _role);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
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
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Brand.textDim)),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  hintText: 'e.g. Tatay, Kuya, Ate…',
                  filled: true,
                  fillColor: Brand.surface,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _continue(),
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
                onPressed: _continue,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.emerald,
                  foregroundColor: Brand.charcoal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Enter the Nest',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
