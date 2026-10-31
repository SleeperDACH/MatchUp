import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/farben.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/matchup_chevron.dart';
import '../../../app/widgets/pill_selector.dart';
import '../../../app/widgets/skelett.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../../../app/home_favorites.dart';
import '../../../core/util/club_logos.dart';
import '../favorites.dart';

/// **Vereinsauswahl beim ersten Start** (29.10.2026, Punkt 5 der
/// Nutzer-Analyse, auf Ansage: „beim ersten Mal starten soll der Nutzer seine
/// Lieblingsteams auswählen — mindestens eins").
///
/// Erscheint nach der Anmeldung, solange im Konto kein Lieblingsverein steht
/// (`vereinsWahlNoetigProvider`, Gate in `main.dart`). Sie ist kein Formular,
/// sondern der erste Blick auf die App: drei Ligen zum Umschalten, Wappen im
/// Raster, ein Knopf. Mit den Vereinen füllt sich der Homescreen (nächstes
/// Spiel, „Mein Wochenende", News) — und erst dann ist die Frage nach
/// Benachrichtigungen „für deinen Verein" eine, die man versteht.
///
/// Gespeichert wird erst bei „Weiter": Ein Zwischenstand nach jedem Tipp
/// würde das Gate schon beim ersten Wappen umschalten.
class VereinsWahlScreen extends ConsumerStatefulWidget {
  const VereinsWahlScreen({super.key});

  @override
  ConsumerState<VereinsWahlScreen> createState() => _VereinsWahlScreenState();
}

class _VereinsWahlScreenState extends ConsumerState<VereinsWahlScreen> {
  static final _ligen = [
    Leagues.bundesliga,
    Leagues.bundesliga2,
    Leagues.liga3,
  ];

  /// Kürzere Namen für die Umschalter — „2. Bundesliga" passt sonst nicht in
  /// eine Pille neben zwei anderen.
  static String _kurz(LeagueInfo l) => switch (l.id) {
    'bundesliga' => 'Bundesliga',
    'bundesliga2' => '2. Liga',
    'liga3' => '3. Liga',
    _ => l.name,
  };

  LeagueInfo _liga = Leagues.bundesliga;

  /// Gewählt: Team-ID → (Team, Liga). Die Reihenfolge der Wahl bleibt
  /// erhalten — der erste Verein steht später oben.
  final _gewaehlt = <String, (TeamRef, String)>{};
  bool _speichert = false;

  void _umschalten(TeamRef team) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_gewaehlt.remove(team.id) == null) {
        _gewaehlt[team.id] = (team, _liga.id);
      }
    });
  }

  Future<void> _weiter() async {
    if (_gewaehlt.isEmpty) return;
    setState(() => _speichert = true);
    final laeuft = ref.read(vereinsWahlLaeuftProvider.notifier);
    // Das Gate wartet, bis der Homescreen fertig aussieht (siehe unten).
    laeuft.state = true;
    try {
      final notifier = ref.read(favoritesProvider.notifier);
      for (final (team, liga) in _gewaehlt.values) {
        await notifier.toggle(Favorite.team(team, liga));
      }
      if (!mounted) return;
      // Hat nichts geklappt (offline), bleibt der Schirm stehen — mit Grund.
      if (ref.read(vereinsWahlNoetigProvider)) {
        setState(() => _speichert = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speichern hat nicht geklappt. Bitte noch einmal.'),
          ),
        );
        return;
      }
      await _homescreenVorladen();
    } finally {
      laeuft.state = false;
    }
  }

  /// **Erst umschalten, wenn die Kopfkarte steht** (31.10.2026): das Spiel
  /// des Vereins samt beiden Wappen und dem Stadionbild. Höchstens 8
  /// Sekunden — danach wird trotzdem umgeschaltet, ein Funkloch darf nicht
  /// auf der Auswahl festhalten. Fehler zählen als fertig.
  Future<void> _homescreenVorladen() async {
    try {
      final spiele = await ref
          .read(favoritenSpieleProvider.future)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      final bilder = <Future<void>>[
        precacheImage(const AssetImage('assets/images/spiel_bg.jpg'), context),
      ];
      if (spiele.isNotEmpty) {
        final s = spiele.first;
        for (final team in [s.home, s.away]) {
          final url = clubLogoUrl(team.name, team.iconUrl);
          if (url != null && !url.toLowerCase().endsWith('.svg')) {
            bilder.add(precacheImage(NetworkImage(url), context));
          }
        }
      }
      await Future.wait(bilder).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Zeitüberschreitung oder Ladefehler: umschalten, der Homescreen zeigt
      // dann, was da ist.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final teams = ref.watch(leagueTeamsProvider(_liga.id));
    final anzahl = _gewaehlt.length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MatchUpChevron(size: 28),
                  const SizedBox(height: 18),
                  const Text(
                    'WÄHLE DEINE VEREINE',
                    style: TextStyle(
                      fontSize: Schrift.gross,
                      fontWeight: Schrift.ueberschriftGewicht,
                      fontStyle: Schrift.ueberschriftStil,
                      letterSpacing: 0.2,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Wir zeigen dir ihre Spiele, Live-Stände und News.',
                    style: TextStyle(
                      fontSize: Schrift.text,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  PillSelector<LeagueInfo>(
                    options: {for (final l in _ligen) l: _kurz(l)},
                    value: _liga,
                    onSelect: (l) => setState(() => _liga = l),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: teams.when(
                loading: () => const Skelett(),
                error: (_, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Die Vereine ließen sich nicht laden.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
                data: (liste) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 116,
                    mainAxisExtent: 104,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: liste.length,
                  itemBuilder: (_, i) => _VereinKachel(
                    team: liste[i],
                    gewaehlt: _gewaehlt.containsKey(liste[i].id),
                    onTap: () => _umschalten(liste[i]),
                  ),
                ),
              ),
            ),
            _Fuss(
              anzahl: anzahl,
              speichert: _speichert,
              onWeiter: anzahl == 0 || _speichert ? null : _weiter,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Verein im Raster: Wappen, Kurzname, gewählt mit der hellen Marke der
/// App und einem grünen Haken — Grün heißt hier „ich".
class _VereinKachel extends StatelessWidget {
  const _VereinKachel({
    required this.team,
    required this.gewaehlt,
    required this.onTap,
  });

  final TeamRef team;
  final bool gewaehlt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farben = context.farben;
    return Semantics(
      button: true,
      selected: gewaehlt,
      label: team.name,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: gewaehlt ? farben.auswahlFlaeche : scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: gewaehlt ? farben.gruen : Theme.of(context).dividerColor,
                width: gewaehlt ? 1.6 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TeamBadge(team: team, size: 44),
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            vereinsKurzname(team.name),
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: Schrift.label + 1,
                              fontWeight: gewaehlt
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: gewaehlt
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: AnimatedScale(
                    scale: gewaehlt ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: farben.gruen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Unten fest: wie viele gewählt sind und „Weiter" — erst ab einem Verein
/// aktiv (auf Ansage: „muss mindestens einen wählen").
class _Fuss extends StatelessWidget {
  const _Fuss({
    required this.anzahl,
    required this.speichert,
    required this.onWeiter,
  });

  final int anzahl;
  final bool speichert;
  final VoidCallback? onWeiter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                anzahl == 0
                    ? 'Mindestens einen Verein wählen'
                    : anzahl == 1
                    ? '1 Verein gewählt'
                    : '$anzahl Vereine gewählt',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Schrift.label + 1,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: onWeiter,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(speichert ? 'Einen Moment …' : 'Weiter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
