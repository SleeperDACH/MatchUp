import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/favorites/ui/favorites_tab.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'theme.dart';
import 'wiedereinstieg.dart';
import 'widgets/liquid_glass.dart';

/// Maße der schwebenden Navi-Kapsel.
///
/// Öffentlich, weil `extendBody: true` die Leiste über den Body legt: Screens,
/// deren Inhalt fest unten endet (Live-Tab), müssen den Platz selbst frei
/// halten und brauchen dafür dieselben Zahlen. Vorher standen sie doppelt im
/// Code — eine Änderung hier hätte den Abstand dort still verschoben.
const double navBarHeight = 60;

/// Mindestabstand der Kapsel zur Bildschirmunterkante. `SafeArea(minimum:)`
/// nimmt davon und dem Geräte-Sicherheitsbereich das **Maximum** — auf einem
/// Gerät mit Home-Indikator greift also dessen Wert, nicht dieser hier.
const double navBarBottomInset = 10;

/// App-Gerüst mit unterer Navigationsleiste: Home · Live · Favoriten. Das
/// Profil ist über den Avatar oben links im Home-Tab erreichbar (kein eigener
/// Tab mehr). Die Tabs liegen im IndexedStack, behalten also ihren Zustand
/// beim Wechseln (Scrollposition, geladene Daten).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Beim Zurückkommen aus dem Hintergrund den Serverstand neu holen.
  ///
  /// Die App hatte vorher gar keinen Lebenszyklus-Beobachter — wer sie
  /// weglegte und wiederholte, sah den Stand von vorher, und es half nur, sie
  /// wirklich zu beenden. Der Beobachter sitzt in der Hülle, damit es für alle
  /// Tabs gilt und nicht je Schirm nachgebaut werden muss.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      beimZurueckkommenAktualisieren(ref);
    }
  }

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
///
/// Bewusst zurückhaltend gehalten — die Leiste ist Navigation, nicht Inhalt:
/// keine gefüllte Auswahl-Pille (die grüne Kapsel war das lauteste Element im
/// Bild), stattdessen trägt allein die Farbe von Symbol und Beschriftung den
/// aktiven Zustand. Dazu eine flachere Kapsel, schwächere Tönung und ein
/// feinerer Rand, damit der Inhalt darüber die Aufmerksamkeit behält.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // Inaktiv gedämpft, aktiv im Markengrün. Der Kontrast zwischen beiden
    // ersetzt die frühere Auswahl-Pille.
    final inaktiv = MatchUpColors.snow.withValues(alpha: 0.55);
    const aktiv = MatchUpColors.green;

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, navBarBottomInset),
      child: LiquidGlass(
        borderRadius: 24,
        blur: 24,
        // Schwächer als der Standard (0.10): die Kapsel soll sich vom Grund
        // abheben, ohne als helle Fläche zu lesen.
        tintOpacity: 0.06,
        borderOpacity: 0.09,
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            // Keine gefüllte Pille mehr hinter dem aktiven Symbol.
            indicatorColor: Colors.transparent,
            indicatorShape: const StadiumBorder(),
            overlayColor: WidgetStatePropertyAll(
                MatchUpColors.snow.withValues(alpha: 0.06)),
            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                  size: 23,
                  color: states.contains(WidgetState.selected) ? aktiv : inaktiv,
                )),
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                  color: states.contains(WidgetState.selected) ? aktiv : inaktiv,
                )),
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            height: navBarHeight,
            selectedIndex: index,
            onDestinationSelected: onSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined),
                selectedIcon: Icon(Icons.sports_soccer),
                label: 'Live',
              ),
              NavigationDestination(
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
