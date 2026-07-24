import 'package:flutter/material.dart';

import '../features/favorites/ui/favorites_tab.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'widgets/liquid_glass.dart';

/// App-Gerüst mit unterer Navigationsleiste: Home · Live · Favoriten. Das
/// Profil ist über den Avatar oben links im Home-Tab erreichbar (kein eigener
/// Tab mehr). Die Tabs liegen im IndexedStack, behalten also ihren Zustand
/// beim Wechseln (Scrollposition, geladene Daten).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = [
    HomeScreen(),
    LiveScreen(),
    FavoritesTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Inhalt läuft hinter der schwebenden Leiste durch → der Blur der
      // Glas-Leiste greift auf den Inhalt (nicht nur den Grund).
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: _GlassNavBar(
        index: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// Schwebende „Liquid Glass"-Navigationsleiste: eine abgerundete Glaskapsel
/// mit Abstand zu den Rändern, echtem Hintergrund-Blur und dezentem Glanz.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: LiquidGlass(
        borderRadius: 28,
        blur: 28,
        child: NavigationBarTheme(
          data: const NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            // Symbole mit weißer Beschriftung (Home · Live · Favoriten).
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            iconTheme: WidgetStatePropertyAll(IconThemeData(size: 24)),
            labelTextStyle: WidgetStatePropertyAll(TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            height: 72,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined),
                selectedIcon: Icon(Icons.sports_soccer),
                label: 'Live',
              ),
              const NavigationDestination(
                icon: Icon(Icons.star_border),
                selectedIcon: Icon(Icons.star),
                label: 'Favoriten',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
