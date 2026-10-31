import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import '../core/logic/vereins_kuerzel.dart';
import '../features/favorites/favorites.dart';
import '../features/push/push_frage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ui/rueckfrage.dart';
import '../features/einladung/einladung.dart';
import '../features/favorites/ui/favorites_tab.dart';
import '../features/leagues/ui/join_by_code.dart';
import '../features/push/push_dienst.dart';
import '../features/push/push_ziel_oeffnen.dart';
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
  bool _pushGestartet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // **Push wird hier angemeldet, nicht in `main()`.** Die Hülle steht erst,
    // wenn jemand angemeldet ist (das Gate lässt sonst den Login stehen) —
    // und genau dann gehört der Token zu einem Konto. Seit Punkt 5 der
    // Nutzer-Analyse (29.10.2026) fragt die App vorher selbst
    // (`_pushPruefen`), sobald der Homescreen steht.
    offeneEinladung.addListener(_einladungPruefen);
  }

  bool _pushGeprueft = false;

  /// **Erst unsere Frage, dann die des Systems** (`push_frage.dart`).
  /// Schon erlaubt → still anmelden. Abgelehnt → nichts (die Systemabfrage
  /// käme ohnehin nicht wieder). Noch offen → kurz nach dem Homescreen das
  /// Blatt „Nichts verpassen", sofern kein „Später" mehr gilt und gerade
  /// keine Einladung gefragt wird.
  Future<void> _pushPruefen() async {
    if (_pushGeprueft || !mounted) return;
    _pushGeprueft = true;
    final dienst = ref.read(pushDienstProvider);
    final status = await dienst.erlaubnisStatus();
    if (status == null || !mounted) return;
    if (status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      _pushAnmelden();
      return;
    }
    if (status == AuthorizationStatus.denied) return;
    if (!await pushFrageFaellig()) return;
    // Einen Augenblick Homescreen, bevor das Blatt kommt — sonst fühlt es
    // sich an wie ein zweiter Ladeschirm.
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted || _einladungOffen) return;
    final verein = ref
        .read(favoritesProvider)
        .where((f) => f.type == FavoriteType.team)
        .map((f) => vereinsKurzname(f.label))
        .firstOrNull;
    final ja = await zeigePushFrage(context, verein: verein);
    if (!mounted) return;
    if (ja) {
      _pushAnmelden();
    } else {
      await pushFrageVertagen();
    }
  }

  /// Eine Einladung per Link annehmen — erst, wenn der Startbildschirm weg ist
  /// (sonst klappte die Rückfrage unter dem Ladeschirm auf), und mit
  /// Rückfrage: Ein Link soll niemanden ungefragt in eine Liga setzen.
  bool _einladungOffen = false;

  Future<void> _einladungPruefen() async {
    final einladung = offeneEinladung.value;
    if (einladung == null || _einladungOffen || !mounted) return;
    if (!ref.read(homeBereitProvider)) return;
    _einladungOffen = true;
    offeneEinladung.value = null;
    try {
      final name = einladung.name;
      final ja = await rueckfrage(
        context,
        titel: 'Einladung annehmen?',
        text: name == null || name.isEmpty
            ? 'Du wurdest mit dem Code ${einladung.code} eingeladen.'
            : 'Du wurdest zu „$name“ eingeladen.',
        ja: 'Beitreten',
      );
      if (ja && mounted) await beitretenMitCode(context, ref, einladung.code);
    } finally {
      _einladungOffen = false;
    }
  }

  void _pushAnmelden() {
    if (_pushGestartet || !mounted) return;
    _pushGestartet = true;
    ref
        .read(pushDienstProvider)
        .starten(
          beimAntippen: (ziel) {
            if (!mounted) return;
            pushZielOeffnen(context, ref, ziel);
          },
        );
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
    if (ref.watch(homeBereitProvider) && !_pushGeprueft) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pushPruefen());
    }
    if (ref.watch(homeBereitProvider) && offeneEinladung.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _einladungPruefen());
    }
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
    offeneEinladung.removeListener(_einladungPruefen);
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

  static const _tabs = [HomeScreen(), LiveScreen(), FavoritesTab()];

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
