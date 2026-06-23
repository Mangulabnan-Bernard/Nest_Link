import 'package:flutter/material.dart';
import 'theme.dart';
import 'services/identity.dart';
import 'services/mesh_service.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Identity.instance.load();
  await MeshService.instance.loadHistory();
  runApp(const NestLinkApp());
}

class NestLinkApp extends StatefulWidget {
  const NestLinkApp({super.key});

  @override
  State<NestLinkApp> createState() => _NestLinkAppState();
}

class _NestLinkAppState extends State<NestLinkApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nest Link',
      debugShowCheckedModeBanner: false,
      theme: buildNestLinkTheme(),
      home: Identity.instance.isSetUp
          ? const HomeShell()
          : OnboardingScreen(onDone: () => setState(() {})),
    );
  }
}
