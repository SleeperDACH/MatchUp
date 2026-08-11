import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'club_screen.dart';
import 'league_overview_screen.dart';
import 'main_shell.dart' show navBarBottomInset, navBarHeight;
import 'match_detail_screen.dart';
import 'theme.dart';
import 'widgets/league_logo.dart';
import 'widgets/pulsing_dot.dart';

/// Signaturfarbe je Wettbewerb (für die Liga-Buttons über dem Datum).
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

/// Live-Tab: oben farbige Liga-Buttons (öffnen die Liga-Übersicht), darunter
/// eine Tagesleiste; gezeigt werden die Spiele des gewählten Tages, nach
/// Wettbewerb gruppiert.
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

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Live'),
      ),
      body: Column(
        children: [
          // Oben die Tagesleiste (scrollbar), darunter die Spiele des
          // gewählten Tages. Ein feiner Strich trennt die Datumsauswahl von
          // der Spielliste. Die Liga-Buttons stehen fest ganz unten.
          _DateStrip(
            days: days,
            today: today,
            selected: _selectedDay,
            controller: _dayController,
            onSelect: (d) => setState(() => _selectedDay = d),
          ),
          const Divider(height: 1),
          Expanded(child: _buildDay(context, items, anyLoading, error)),
          // Feiner Strich, der die Liga-Buttons von der Spielliste abtrennt.
          const Divider(height: 1),
          // Farbige Liga-Buttons — Antippen öffnet die Liga-Übersicht
          // (Spieltage, Tabelle, Torjäger, News).
          _LeagueButtons(
            onOpen: (id) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    LeagueOverviewScreen(league: Leagues.byId(id)))),
          ),
          // Abstand zur schwebenden Navi-Leiste. Die Leiste ist nicht Teil
          // dieser Column (`extendBody` in der MainShell), ihr Platz muss hier
          // also selbst frei gehalten werden: Kapselhöhe + deren unterer Rand
          // + Geräte-Sicherheitsbereich, dazu die sichtbare Lücke — ohne die
          // kleben die Liga-Buttons an der Kapsel.
          SizedBox(
              height: math.max(MediaQuery.viewPaddingOf(context).bottom,
                      navBarBottomInset) +
                  navBarHeight +
                  _navBarGap),
        ],
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
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: leagueIds.length,
              itemBuilder: (context, i) => _LeagueBox(
                league: Leagues.byId(leagueIds[i]),
                items: byLeague[leagueIds[i]]!,
              ),
            ),
    );
  }

  void _refresh() {
    for (final l in Leagues.all) {
      ref.invalidate(leagueSeasonFixturesProvider(l.id));
    }
  }
}

/// Farbige Liga-Buttons über dem Datum. 1. + 2. Bundesliga stehen groß in der
/// oberen Reihe, die übrigen drei kleiner darunter — alle fünf ohne Wischen
/// sichtbar. Antippen öffnet die Liga-Übersicht (kein Filter).
class _LeagueButtons extends StatelessWidget {
  const _LeagueButtons({required this.onOpen});

  final ValueChanged<String> onOpen;

  static const _big = ['bundesliga', 'bundesliga2'];
  static const _small = ['liga3', 'dfb_pokal', 'frauen_bundesliga'];
  static const _shortLabel = {
    'liga3': '3. Liga',
    'dfb_pokal': 'DFB-Pokal',
    'frauen_bundesliga': 'Frauen',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              for (final id in _big) ...[
                Expanded(
                  child: _LeagueButton(
                    leagueId: id,
                    label: Leagues.byId(id).name,
                    color: leagueColor(id),
                    big: true,
                    onTap: () => onOpen(id),
                  ),
                ),
                if (id != _big.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final id in _small) ...[
                Expanded(
                  child: _LeagueButton(
                    leagueId: id,
                    label: _shortLabel[id]!,
                    color: leagueColor(id),
                    big: false,
                    onTap: () => onOpen(id),
                  ),
                ),
                if (id != _small.last) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Schlichter, flacher Liga-Button: Liga-Logo + Name in der Liga-Farbe, ohne
/// Box/Rahmen. Antippen öffnet die Liga-Übersicht.
class _LeagueButton extends StatelessWidget {
  const _LeagueButton({
    required this.leagueId,
    required this.label,
    required this.color,
    required this.big,
    required this.onTap,
  });

  final String leagueId;
  final String label;
  final Color color;
  final bool big;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final logo = leagueLogoUrl(leagueId);
    final logoSize = big ? 26.0 : 18.0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: big ? 10 : 8, horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (logo != null) ...[
              LeagueLogo(
                leagueId: leagueId,
                size: logoSize,
                fallback:
                    Icon(Icons.emoji_events, size: logoSize, color: color),
              ),
              SizedBox(width: big ? 8 : 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: big ? 15 : 12,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: big ? 18 : 14, color: color.withValues(alpha: 0.7)),
          ],
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
    required this.onSelect,
    this.controller,
  });

  final List<DateTime> days;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Die Trennlinie zur Spielliste liefert der Divider darunter (im
    // Live-Tab), daher hier kein eigener unterer Rand mehr.
    return SizedBox(
        height: 62,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final d = days[i];
            final sel = _sameDay(d, selected);
            final isToday = _sameDay(d, today);
            return GestureDetector(
              onTap: () => onSelect(d),
              child: Container(
                width: 52,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !sel
                      ? Border.all(color: scheme.primary)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE', 'de_DE').format(d),
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            sel ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: sel
                            ? scheme.onPrimary
                            : (isToday ? scheme.primary : scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
    );
  }
}

/// Alle Spiele **einer** Liga an diesem Tag in einer Box.
///
/// Der Liga-Kopf ersetzt das Kürzel an jeder Begegnung. Innerhalb der Box
/// stehen die Spiele nach Anstoßzeit; wechselt die Anstoßzeit, trennt eine
/// feine Linie — Spiele derselben Anstoßzeit bleiben als Block zusammen, so
/// wie man einen Spieltag liest.
class _LeagueBox extends StatelessWidget {
  const _LeagueBox({required this.league, required this.items});

  final LeagueInfo league;
  final List<_LiveItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final farbe = leagueColor(league.id);

    final zeilen = <Widget>[];
    DateTime? letzteZeit;
    for (final it in items) {
      final zeit = it.fixture.kickoff;
      if (letzteZeit != null && zeit != letzteZeit) {
        zeilen.add(Divider(
          height: 1,
          thickness: 1,
          indent: 12,
          endIndent: 12,
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ));
      }
      letzteZeit = zeit;
      zeilen.add(_MatchTile(item: it));
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                LeagueLogo(
                  leagueId: league.id,
                  size: 18,
                  fallback: Icon(Icons.emoji_events, size: 18, color: farbe),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    league.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: farbe,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: -0.2),
                  ),
                ),
                Text('${items.length}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ...zeilen,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.item});
  final _LiveItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = item.fixture;
    final live = f.status == FixtureStatus.live;
    final finished = f.status == FixtureStatus.finished;

    final scoreOrTime = SizedBox(
      width: 70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (f.hasScore)
            // Score wechselt animiert (Tor-Effekt): bei Live-Spielen skaliert
            // der neue Stand kurz ein, sobald ein Tor fällt.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              transitionBuilder: (child, anim) => ScaleTransition(
                  scale: Tween(begin: 0.6, end: 1.0).animate(anim),
                  child: FadeTransition(opacity: anim, child: child)),
              child: Text('${f.homeScore}:${f.awayScore}',
                  key: ValueKey('${f.homeScore}:${f.awayScore}'),
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: live ? MatchUpColors.red : scheme.onSurface)),
            )
          else
            Text(DateFormat('HH:mm').format(f.kickoff.toLocal()),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          if (live)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                PulsingDot(size: 7),
                SizedBox(width: 4),
                Text('LIVE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: MatchUpColors.red)),
              ],
            )
          else
            Text(finished ? 'beendet' : 'Anstoß',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );

    // Keine eigene Karte mehr: Die Zeile sitzt in der Liga-Box. Der rote
    // Akzent für laufende Spiele bleibt (Tönung + Streifen links).
    return Material(
      color: live ? MatchUpColors.red.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(fixtureId: f.id))),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Platzhalter gleicher Breite, damit die Mannschaftsnamen
              // untereinander fluchten — mit und ohne Live-Streifen.
              Container(
                  width: 4, color: live ? MatchUpColors.red : Colors.transparent),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  child: Row(
                    children: [
                      Expanded(child: _TeamSide(team: f.home)),
                      scoreOrTime,
                      Expanded(child: _TeamSide(team: f.away, alignEnd: true)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, this.alignEnd = false});
  final TeamRef team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    // Das Wappen öffnet die Vereinsseite; der Rest der Kachel bleibt der
    // Spielansicht vorbehalten.
    final badge = ClubLink(team: team, child: TeamBadge(team: team));
    final label = Flexible(
      child: Text(team.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [label, const SizedBox(width: 8), badge]
          : [badge, const SizedBox(width: 8), label],
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
