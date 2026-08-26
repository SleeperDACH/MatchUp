import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'club_screen.dart';
import 'home_screen.dart' show minTastflaeche;
import 'league_overview_screen.dart';
import 'main_shell.dart' show navBarBottomInset, navBarHeight;
import 'match_detail_screen.dart';
import 'theme.dart';
import 'widgets/league_logo.dart';
import 'widgets/pulsing_dot.dart';

/// Signaturfarbe je Wettbewerb — im Quadrat vor dem Liganamen, in der
/// Wettbewerbszeile unten und im Auswahl-Sheet.
Color leagueColor(String leagueId) => switch (leagueId) {
      'bundesliga' => const Color(0xFFD20515), // Bundesliga-Rot
      'bundesliga2' => const Color(0xFF2E6BE6), // Blau
      'liga3' => const Color(0xFFEF7D00), // Orange
      'dfb_pokal' => const Color(0xFFFFC83D), // Pokal-Gold
      'frauen_bundesliga' => const Color(0xFFE0218A), // Magenta
      _ => const Color(0xFF4ADE6A),
    };

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Ein Spiel im Live-Feed, samt zugehöriger Liga.
class _LiveItem {
  const _LiveItem(this.league, this.fixture);
  final LeagueInfo league;
  final Fixture fixture;
}

/// Live-Tab als **Tafel**: Kopfzeile mit dem Tag und dem, was gerade läuft,
/// darunter die Tagesleiste, dann die Spiele des gewählten Tages als
/// durchgehende Liste — je Wettbewerb eine schmale Kopfzeile, die Spiele als
/// Haarlinien darunter. Ganz unten eine Zeile zu den Wettbewerben.
///
/// Vorher saß jede Liga in einer eigenen Karte mit Rahmen, „Live" stand als
/// größte Schrift oben, und fünf farbige Liga-Knöpfe klebten fest am unteren
/// Rand. Was daran nicht trug, steht in `design/live/` — die Diagnose und die
/// drei Richtungen, aus denen „B — Tafel" gewählt wurde.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  late DateTime _selectedDay;
  ScrollController? _dayController;
  Timer? _refreshTimer;

  static const _dayItemExtent = 60.0; // Breite + Rand je Tageszelle

  // Lücke, die über der schwebenden Navi-Kapsel frei bleiben soll. Deren
  // eigene Maße kommen aus `main_shell.dart` — nicht hier nachbilden.
  static const _navBarGap = 32.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    // Eigener Takt (unabhängig von Rebuilds): lädt die Spieldaten neu,
    // solange ein Spiel live ist bzw. zeitnah ansteht/gerade lief — sonst
    // nur ein günstiger Check auf zwischengespeicherten Daten, kein Abruf.
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => _maybeRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dayController?.dispose();
    super.dispose();
  }

  void _maybeRefresh() {
    if (!mounted) return;
    final now = DateTime.now();
    var hasNear = false;
    for (final l in Leagues.all) {
      final fx = ref.read(leagueSeasonFixturesProvider(l.id)).valueOrNull;
      if (fx == null) continue;
      if (fx.any((f) =>
          f.status != FixtureStatus.finished &&
          f.kickoff.difference(now).abs() < const Duration(hours: 3))) {
        hasNear = true;
        break;
      }
    }
    if (!hasNear) return;
    for (final l in Leagues.all) {
      ref.invalidate(leagueSeasonFixturesProvider(l.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Der Live-Tab zeigt immer alle Wettbewerbe (in Registry-Reihenfolge) —
    // kein Filtern/Sortieren nach Favoriten mehr.
    final leagueIds = [for (final l in Leagues.all) l.id];

    // Fixtures der relevanten Ligen einsammeln (best effort).
    final items = <_LiveItem>[];
    var anyLoading = false;
    Object? error;
    for (final id in leagueIds) {
      final async = ref.watch(leagueSeasonFixturesProvider(id));
      if (async.isLoading) {
        anyLoading = true;
      } else if (async.hasError) {
        error ??= async.error;
      } else {
        final league = Leagues.byId(id);
        for (final f in async.valueOrNull ?? const <Fixture>[]) {
          items.add(_LiveItem(league, f));
        }
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = -7; i <= 7; i++) today.add(Duration(days: i))];
    // Heute (Index 7) beim ersten Aufbau etwa mittig einblenden.
    _dayController ??= ScrollController(
        initialScrollOffset: (7 * _dayItemExtent - 120).clamp(0, 1e9));

    // Tage, an denen überhaupt gespielt wird, und die mit laufendem Spiel —
    // die Tagesleiste soll zeigen, wo etwas los ist, statt fünfzehn gleiche
    // Zellen zu zeigen, durch die man sich tippen muss.
    final mitSpielen = <DateTime>{};
    final mitLive = <DateTime>{};
    for (final it in items) {
      final lt = it.fixture.kickoff.toLocal();
      final tag = DateTime(lt.year, lt.month, lt.day);
      mitSpielen.add(tag);
      if (it.fixture.status == FixtureStatus.live) mitLive.add(tag);
    }
    final liveHeute = [
      for (final it in items)
        if (it.fixture.status == FixtureStatus.live &&
            _sameDay(it.fixture.kickoff.toLocal(), _selectedDay))
          it,
    ].length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Kopfzeile: der gewählte Tag, und rechts, was gerade läuft. Der
            // Titel „Live" stand hier als größte Schrift des Schirms und trug
            // keine Information — in welchem Tab man ist, sagt die Navileiste.
            _Kopf(tag: _selectedDay, live: liveHeute),
            _DateStrip(
              days: days,
              today: today,
              selected: _selectedDay,
              controller: _dayController,
              mitSpielen: mitSpielen,
              mitLive: mitLive,
              onSelect: (d) => setState(() => _selectedDay = d),
            ),
            Expanded(child: _buildDay(context, items, anyLoading, error)),
            // Die fünf Wettbewerbe in **einer** Zeile. Vorher stand hier eine
            // festgenagelte Leiste aus fünf verschiedenfarbigen Knöpfen in
            // zwei Reihen: rund 90 Punkte Dauerbild, mehr Signalfarben als im
            // Rest der App zusammen, und eine Navigationsleiste direkt über
            // der Navigationsleiste.
            _WettbewerbeZeile(
              onOpen: (id) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      LeagueOverviewScreen(league: Leagues.byId(id)),
                ),
              ),
            ),
            // Abstand zur schwebenden Navi-Leiste. Die Leiste ist nicht Teil
            // dieser Column (`extendBody` in der MainShell), ihr Platz muss
            // hier also selbst frei gehalten werden.
            SizedBox(
              height:
                  math.max(MediaQuery.viewPaddingOf(context).bottom,
                          navBarBottomInset) +
                      navBarHeight +
                      _navBarGap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDay(
      BuildContext context, List<_LiveItem> items, bool anyLoading, Object? error) {
    if (items.isEmpty && anyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty && error != null) {
      return _Retry(
        message: 'Spiele konnten nicht geladen werden.',
        onRetry: _refresh,
      );
    }

    // Spiele des gewählten Tages, nach Wettbewerb gebündelt: eine Box je Liga,
    // darin nach Anstoßzeit von früh nach spät. Die Liga steht damit einmal am
    // Kopf der Box statt als Kürzel an jeder einzelnen Begegnung.
    final list = [
      for (final it in items)
        if (_sameDay(it.fixture.kickoff.toLocal(), _selectedDay)) it
    ];

    final byLeague = <String, List<_LiveItem>>{};
    for (final it in list) {
      byLeague.putIfAbsent(it.league.id, () => []).add(it);
    }
    for (final l in byLeague.values) {
      l.sort((a, b) => a.fixture.kickoff.compareTo(b.fixture.kickoff));
    }
    // Reihenfolge der Boxen = Registry-Reihenfolge (1. BL, 2. BL, 3. Liga, …),
    // nicht die zufällige Reihenfolge der Anstoßzeiten.
    final leagueIds = [
      for (final l in Leagues.all)
        if (byLeague.containsKey(l.id)) l.id
    ];

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: list.isEmpty
          ? const _Empty('Keine Spiele an diesem Tag.')
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Eine durchgehende Fläche: je Wettbewerb eine schmale
                // Kopfzeile, darunter die Spiele als Haarlinien-Liste. Vorher
                // saß jede Liga in einer eigenen Karte mit Rahmen und Radius
                // — fünf Rahmen untereinander, und der Wettbewerb stand
                // dreimal darin (Logo, Name in Ligafarbe, Anzahl).
                for (final id in leagueIds) ...[
                  _LigaKopf(
                    league: Leagues.byId(id),
                    anzahl: byLeague[id]!.length,
                  ),
                  for (var i = 0; i < byLeague[id]!.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 0.8,
                        thickness: 0.8,
                        indent: 16,
                        endIndent: 16,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.07),
                      ),
                    _SpielZeile(item: byLeague[id]![i]),
                  ],
                ],
              ],
            ),
    );
  }

  void _refresh() {
    for (final l in Leagues.all) {
      ref.invalidate(leagueSeasonFixturesProvider(l.id));
    }
  }
}

/// Kopfzeile des Live-Tabs: der gewählte Tag, und rechts, was gerade läuft.
///
/// Hier stand „Live" als 24-Punkte-Titel — die größte Schrift des Schirms für
/// eine Auskunft, die die Navileiste schon gibt. Der Tag trägt sie jetzt, und
/// die rechte Seite beantwortet die Frage, für die es den Tab gibt. Läuft
/// nichts, bleibt sie leer: eine „0 live" wäre eine Meldung über nichts.
class _Kopf extends StatelessWidget {
  const _Kopf({required this.tag, required this.live});

  final DateTime tag;
  final int live;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              DateFormat('EEEE, d. MMM', 'de_DE').format(tag),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (live > 0) ...[
            const SizedBox(width: 8),
            const PulsingDot(size: 8),
            const SizedBox(width: 6),
            Text(
              live == 1 ? '1 live' : '$live live',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MatchUpColors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kopfzeile eines Wettbewerbs in der Tafel — eine schmale, leicht abgesetzte
/// Zeile statt einer Karte mit Rahmen.
///
/// Der Name steht **nicht** mehr in der Ligafarbe: Fünf farbige Überschriften
/// untereinander riefen gleich laut, und die Farbe sagt ohnehin das Quadrat
/// davor. So bleibt Farbe für das übrig, was gerade läuft.
class _LigaKopf extends StatelessWidget {
  const _LigaKopf({required this.league, required this.anzahl});

  final LeagueInfo league;
  final int anzahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farbe = leagueColor(league.id);
    return Container(
      color: scheme.onSurface.withValues(alpha: 0.03),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          LeagueLogo(
            leagueId: league.id,
            size: 14,
            fallback: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: farbe,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              league.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
          ),
          Text(
            '$anzahl',
            style: TextStyle(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ein Spiel als Zeile der Tafel: Namen zur Mitte hin, Ergebnis oder Anstoß
/// dazwischen, Wappen an den Außenkanten.
///
/// Der Entwurf („Richtung B") hatte die Wappen weggelassen — dichter, ruhiger.
/// Sie sind trotzdem geblieben, klein und außen: Sie tragen das Wiedererkennen
/// auf einen Blick, und über sie führt der **einzige** Weg vom Live-Tab auf
/// eine Vereinsseite ([ClubLink]). Ohne sie wäre der Weg still verschwunden.
///
/// „Anstoß" unter der Uhrzeit ist weg — das sagte dasselbe zweimal. „beendet"
/// bleibt, denn einem 3:2 sieht man nicht an, ob es das Endergebnis ist.
class _SpielZeile extends StatelessWidget {
  const _SpielZeile({required this.item});

  final _LiveItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = item.fixture;
    final live = f.status == FixtureStatus.live;
    final finished = f.status == FixtureStatus.finished;

    return Material(
      color: live
          ? MatchUpColors.red.withValues(alpha: 0.07)
          : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MatchDetailScreen(fixtureId: f.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
          child: Row(
            children: [
              ClubLink(team: f.home, child: TeamBadge(team: f.home, size: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  f.home.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 62,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (f.hasScore)
                      // Der Stand wechselt animiert: bei einem Tor skaliert
                      // die neue Zahl kurz ein.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, anim) => ScaleTransition(
                          scale: Tween(begin: 0.6, end: 1.0).animate(anim),
                          child: FadeTransition(opacity: anim, child: child),
                        ),
                        child: Text(
                          '${f.homeScore}:${f.awayScore}',
                          key: ValueKey('${f.homeScore}:${f.awayScore}'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: live
                                ? MatchUpColors.red
                                : scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      )
                    else
                      Text(
                        DateFormat('HH:mm').format(f.kickoff.toLocal()),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (finished)
                      Text(
                        'beendet',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  f.away.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ClubLink(team: f.away, child: TeamBadge(team: f.away, size: 18)),
              // Der Live-Punkt sitzt an der Außenkante — kein 4-px-Streifen
              // mehr, der die Zeile gegen die anderen verschiebt.
              SizedBox(
                width: 13,
                child: live
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: PulsingDot(size: 7),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die fünf Wettbewerbe in einer Zeile, ganz unten.
///
/// Vorher standen hier fünf farbige Knöpfe in zwei Reihen: rund 90 Punkte
/// Dauerbild und fünf Signalfarben — mehr, als der Rest der App zusammen
/// benutzt. Jetzt eine Zeile; die Farben stecken in den Quadraten davor und
/// die Auswahl kommt erst auf Tippen.
class _WettbewerbeZeile extends StatelessWidget {
  const _WettbewerbeZeile({required this.onOpen});

  final ValueChanged<String> onOpen;

  Future<void> _waehlen(BuildContext context) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in Leagues.all)
              ListTile(
                leading: LeagueLogo(
                  leagueId: l.id,
                  size: 24,
                  fallback: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: leagueColor(l.id),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
                title: Text(l.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(sheetContext).pop(l.id),
              ),
          ],
        ),
      ),
    );
    if (id != null) onOpen(id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _waehlen(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: BoxConstraints(minHeight: minTastflaeche(context)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                for (final l in Leagues.all) ...[
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: leagueColor(l.id),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'Wettbewerbe',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tagesleiste: letzte 7 und nächste 7 Tage; tippen wählt den Tag.
class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.days,
    required this.today,
    required this.selected,
    required this.mitSpielen,
    required this.mitLive,
    required this.onSelect,
    this.controller,
  });

  final List<DateTime> days;
  final DateTime today;
  final DateTime selected;

  /// Tage, an denen überhaupt gespielt wird — sie bekommen einen Punkt.
  final Set<DateTime> mitSpielen;

  /// Tage mit laufendem Spiel — deren Punkt ist rot.
  final Set<DateTime> mitLive;

  final ValueChanged<DateTime> onSelect;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 66,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: days.length,
        itemBuilder: (context, i) {
          final d = days[i];
          final sel = _sameDay(d, selected);
          final isToday = _sameDay(d, today);
          final hatSpiele = mitSpielen.any((t) => _sameDay(t, d));
          final hatLive = mitLive.any((t) => _sameDay(t, d));
          // Der Punkt beantwortet, wofür man sich vorher durch fünfzehn
          // gleiche Zellen tippen musste: Wird an dem Tag gespielt? Rot
          // heißt, dort läuft gerade etwas.
          final punkt = hatLive
              ? MatchUpColors.red
              : (hatSpiele ? scheme.onSurfaceVariant : Colors.transparent);
          return Semantics(
            button: true,
            selected: sel,
            label: [
              DateFormat('EEEE, d. MMMM', 'de_DE').format(d),
              if (hatLive) 'Spiele laufen' else if (hatSpiele) 'Spieltag',
            ].join(', '),
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => onSelect(d),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 52,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  // Ausgewählt ist hell, nicht grün: Auf einer Tafel, deren
                  // einzige Farbe „hier läuft etwas" heißt, wäre ein grüner
                  // Klotz ein Signal ohne Anlass.
                  color: sel ? scheme.onSurface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !sel
                      ? Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.35),
                        )
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE', 'de_DE').format(d),
                      style: TextStyle(
                        fontSize: 11,
                        color: sel ? scheme.surface : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: sel
                            ? scheme.surface
                            : (hatSpiele
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant.withValues(
                                      alpha: 0.55,
                                    )),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: sel && punkt != Colors.transparent
                            ? scheme.surface
                            : punkt,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Column(
            children: [
              Icon(Icons.event_busy,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
        ],
      ),
    );
  }
}
