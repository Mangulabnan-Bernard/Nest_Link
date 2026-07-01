import 'package:flutter/material.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'nest_mat_screen.dart';
import 'chirp_chat_screen.dart';
import 'safe_flight_screen.dart';
import 'me_screen.dart';

/// Root scaffold — Home command center + the feature tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final tabs = [
      HomeScreen(onNavigate: _go),
      const ChirpChatScreen(),
      const NestMatScreen(),
      const SafeFlightScreen(),
      const MeScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: Brand.emerald),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble, color: Brand.emerald),
              label: 'Chat'),
          NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: Brand.emerald),
              label: 'Map'),
          NavigationDestination(
              icon: Icon(Icons.shield_outlined),
              selectedIcon: Icon(Icons.shield, color: Brand.emerald),
              label: 'Safety'),
          NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: Brand.emerald),
              label: 'Me'),
        ],
      ),
    );
  }
}
