import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/favorites/ui/favorites_tab.dart';
import 'home_screen.dart';
import 'live_screen.dart';
import 'wiedereinstieg.dart';
import 'widgets/navi_kapsel.dart';
import 'vorwaermen.dart';
import 'widgets/matchup_splash.dart';

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
  bool _vorgewaermt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  Widget build(BuildContext context) {
    // **Der Unterbau wird geholt, sobald der Startbildschirm steht.**
    //
    // Gemeldet: *„Auch bei guter Internetverbindung sind ganz oft
    // Ladescreens."* Spielerpool, Saison-Spielplan und die Saison-Statistik
    // hängen an fast jedem Fantasy-Schirm — geholt wurden sie aber erst, wenn
    // einer davon offen war. Jetzt laufen sie, während der Nutzer noch auf den
    // Startbildschirm schaut.
    //
    // **Erst nach `homeBereitProvider`**, nicht sofort: Der Startschirm wartet
    // auf vier eigene Abfragen, und die dürfen sich nicht mit fünf weiteren um
    // die Leitung streiten. Genau einmal je Sitzung — ein `build` läuft bei
    // jedem Reiterwechsel.
    if (!_vorgewaermt && ref.watch(homeBereitProvider)) {
      _vorgewaermt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) warmeFantasyUnterbau(ref);
      });
    }
    return _bauen(context);
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

  Widget _bauen(BuildContext context) {
    return Scaffold(
      // Inhalt läuft hinter der schwebenden Leiste durch → der Blur der
      // Glas-Leiste greift auf den Inhalt (nicht nur den Grund).
      extendBody: true,
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NaviKapsel(
        index: _index,
        onSelected: (i) => setState(() => _index = i),
      ),
    );
  }
}
