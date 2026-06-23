import 'package:flutter/material.dart';
import '../theme.dart';
import 'nest_mat_screen.dart';
import 'chirp_chat_screen.dart';
import 'safe_flight_screen.dart';
import 'mesh_test_screen.dart';

/// Root scaffold with the four Nest Link tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    NestMatScreen(),
    ChirpChatScreen(),
    SafeFlightScreen(),
    MeshTestScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: Brand.emerald),
              label: 'Nest Mat'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble, color: Brand.emerald),
              label: 'Chirp'),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield, color: Brand.emerald),
              label: 'Safe Flight'),
          NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub, color: Brand.emerald),
              label: 'Live'),
        ],
      ),
    );
  }
}
