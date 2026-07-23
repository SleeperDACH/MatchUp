import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/match_detail.dart';
import '../core/models/models.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'theme.dart';
import 'widgets/pulsing_dot.dart';

/// Spiel-Detailansicht mit Tabs: Übersicht (Ergebnis, Spielverlauf,
/// Torschützen), Aufstellung, Statistik und (Live-)Tabelle. Quelle: Sportmonks.
class MatchDetailScreen extends ConsumerStatefulWidget {
  const MatchDetailScreen({super.key, required this.fixtureId});

  final String fixtureId;

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Auto-Aktualisierung nur, solange das Spiel läuft.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final d = ref.read(matchDetailProvider(widget.fixtureId)).valueOrNull;
      if (d?.status == FixtureStatus.live) {
        ref.invalidate(matchDetailProvider(widget.fixtureId));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async =>
      ref.invalidate(matchDetailProvider(widget.fixtureId));

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(matchDetailProvider(widget.fixtureId));
    return Scaffold(
      appBar: AppBar(title: const Text('Spieldetails')),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Spieldaten konnten nicht geladen werden.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _refresh,
                  child: const Text('Erneut laden'),
                ),
              ],
            ),
          ),
        ),
        data: (d) {
          final league = Leagues.bySportmonksKey(d.leagueKey);
          final showTable = league != null && league.id != 'dfb_pokal';
          final tabs = <Tab>[
            const Tab(text: 'Übersicht'),
            if (d.lineups.isNotEmpty) const Tab(text: 'Aufstellung'),
            if (d.stats.isNotEmpty) const Tab(text: 'Statistik'),
            if (showTable) const Tab(text: 'Tabelle'),
          ];
          final views = <Widget>[
            _OverviewTab(detail: d, onRefresh: _refresh),
            if (d.lineups.isNotEmpty) _LineupTab(detail: d),
            if (d.stats.isNotEmpty) _StatsTab(detail: d),
            if (showTable) _TableTab(leagueId: league.id, detail: d),
          ];
          return DefaultTabController(
            length: tabs.length,
            child: Column(
              children: [
                _Header(detail: d),
                Material(
                  color: Theme.of(context).appBarTheme.backgroundColor,
                  child: TabBar(isScrollable: tabs.length > 3, tabs: tabs),
                ),
                Expanded(child: TabBarView(children: views)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Kopf: Wappen, Ergebnis/Anstoß, Status
// ---------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = detail;
    final live = d.status == FixtureStatus.live;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _TeamColumn(team: d.home)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (d.hasScore)
                  Text('${d.homeScore}:${d.awayScore}',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: live ? MatchUpColors.red : scheme.onSurface))
                else
                  Column(
                    children: [
                      Text(DateFormat('HH:mm').format(d.kickoff.toLocal()),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                          DateFormat('d. MMM', 'de_DE')
                              .format(d.kickoff.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                    ],
                  ),
                const SizedBox(height: 6),
                if (detail.halfTime != null)
                  Text('(${detail.halfTime!.$1}:${detail.halfTime!.$2})',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant)),
                if (live)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      PulsingDot(size: 7),
                      SizedBox(width: 4),
                      Text('LIVE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: MatchUpColors.red)),
                    ],
                  )
                else if (d.status == FixtureStatus.finished)
                  Text('beendet',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(child: _TeamColumn(team: d.away)),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({required this.team});
  final TeamRef team;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TeamBadge(team: team, size: 46),
        const SizedBox(height: 8),
        Text(team.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Übersicht: Zusatzergebnisse, Spielort, Spielverlauf
// ---------------------------------------------------------------------
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.detail, required this.onRefresh});
  final MatchDetail detail;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _ResultLines(detail: d),
          if (d.stadium != null || d.city != null) ...[
            const SizedBox(height: 10),
            _Location(stadium: d.stadium, city: d.city),
          ],
          const SizedBox(height: 18),
          Text('Spielverlauf', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Timeline(detail: d),
        ],
      ),
    );
  }
}

/// Halbzeit / nach Verlängerung / Elfmeterschießen, sofern vorhanden.
class _ResultLines extends StatelessWidget {
  const _ResultLines({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = <(String, (int, int))>[
      if (detail.halfTime != null) ('Halbzeit', detail.halfTime!),
      if (detail.afterExtraTime != null)
        ('nach Verlängerung', detail.afterExtraTime!),
      if (detail.penalties != null) ('Elfmeterschießen', detail.penalties!),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (label, (h, a)) in lines)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$label  $h:$a',
                style: Theme.of(context).textTheme.labelMedium),
          ),
      ],
    );
  }
}

class _Location extends StatelessWidget {
  const _Location({this.stadium, this.city});
  final String? stadium;
  final String? city;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text =
        [stadium, city].where((e) => e != null && e.isNotEmpty).join(' · ');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.place_outlined, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// Chronologischer Spielverlauf aus den Events (Tore, Karten, Wechsel, VAR).
class _Timeline extends StatelessWidget {
  const _Timeline({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Relevante Ereignisse — gelbe Karten bewusst nicht im Verlauf (die stehen
    // an den Spielern in der Aufstellung).
    final events = [
      for (final e in detail.events)
        if (_iconFor(e.type) != null && e.type.toLowerCase() != 'yellowcard') e
    ];
    if (events.isEmpty) {
      final msg = detail.status == FixtureStatus.scheduled
          ? 'Das Spiel hat noch nicht begonnen.'
          : 'Keine Verlaufsdaten verfügbar.';
      return Text(msg,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant));
    }
    return Column(children: [for (final e in events) _EventRow(event: e)]);
  }
}

/// Symbol je Ereignistyp; null = nicht anzeigen.
IconData? _iconFor(String type) {
  switch (type.toLowerCase()) {
    case 'goal':
    case 'owngoal':
    case 'penalty':
      return Icons.sports_soccer;
    case 'yellowcard':
    case 'yellowredcard':
    case 'redcard':
      return Icons.rectangle;
    case 'substitution':
      return Icons.swap_horiz;
    case 'var':
      return Icons.tv;
    default:
      return null;
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final MatchEvent event;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = event;
    final t = e.type.toLowerCase();
    final isGoal = t.contains('goal') || t == 'penalty';
    final color = switch (t) {
      'yellowcard' => const Color(0xFFFFC83D),
      'redcard' || 'yellowredcard' => MatchUpColors.red,
      'goal' || 'owngoal' || 'penalty' => MatchUpColors.green,
      _ => scheme.onSurfaceVariant,
    };
    // Wechsel: grüner Pfeil rein, roter Pfeil raus.
    final Widget icon = t == 'substitution'
        ? const _SubArrows()
        : Icon(_iconFor(e.type) ?? Icons.circle,
            size: t.contains('card') ? 12 : 16, color: color);
    final minute = Text(
        e.extra != null ? "${e.minute}+${e.extra}'" : "${e.minute}'",
        style: TextStyle(fontWeight: FontWeight.bold, color: scheme.primary));
    final label = Column(
      crossAxisAlignment:
          e.forHomeTeam ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Text(e.player ?? e.type,
            style: const TextStyle(fontWeight: FontWeight.w600),
            textAlign: e.forHomeTeam ? TextAlign.start : TextAlign.end),
        if (e.related != null)
          Text(
              t == 'substitution' ? 'für ${e.related}' : e.related!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        if (isGoal && e.result != null)
          Text(e.result!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
    final children = e.forHomeTeam
        ? [
            SizedBox(width: 40, child: minute),
            const SizedBox(width: 4),
            icon,
            const SizedBox(width: 8),
            Expanded(child: label),
            const Expanded(child: SizedBox()),
          ]
        : [
            const Expanded(child: SizedBox()),
            Expanded(child: label),
            const SizedBox(width: 8),
            icon,
            const SizedBox(width: 4),
            SizedBox(
                width: 40,
                child: Align(alignment: Alignment.centerRight, child: minute)),
          ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: children),
    );
  }
}

/// Wechsel-Symbol: grüner Pfeil (rein) über rotem Pfeil (raus).
class _SubArrows extends StatelessWidget {
  const _SubArrows();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward, size: 12, color: MatchUpColors.green),
          Icon(Icons.arrow_downward, size: 12, color: MatchUpColors.red),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Aufstellung
// ---------------------------------------------------------------------
class _LineupTab extends StatelessWidget {
  const _LineupTab({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    List<LineupPlayer> pick(bool home, bool starting) => [
          for (final p in d.lineups)
            if (p.forHomeTeam == home && p.starting == starting) p
        ]..sort((a, b) => (a.position ?? 99).compareTo(b.position ?? 99));
    final startHome = pick(true, true);
    final startAway = pick(false, true);
    // Karten je Spieler (aus den Events) für die Anzeige am Feld.
    final yellow = <int>{};
    final red = <int>{};
    for (final e in d.events) {
      final id = e.playerId;
      if (id == null) continue;
      final t = e.type.toLowerCase();
      if (t == 'yellowcard') yellow.add(id);
      if (t == 'redcard' || t == 'yellowredcard') red.add(id);
    }
    // Feld nur zeigen, wenn Rasterpositionen vorhanden sind.
    final hasGrid = startHome.any((p) => p.row != null) &&
        startAway.any((p) => p.row != null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        if (hasGrid) ...[
          _FormationLabels(detail: d),
          const SizedBox(height: 8),
          _PitchLineup(
            home: startHome,
            away: startAway,
            yellow: yellow,
            red: red,
          ),
        ] else
          _LineupBlock(title: 'Startelf', home: startHome, away: startAway),
        const SizedBox(height: 20),
        _LineupBlock(
          title: 'Bank',
          home: pick(true, false),
          away: pick(false, false),
        ),
      ],
    );
  }
}

/// Formationsangaben (z. B. „4-2-3-1" · Heim / Auswärts „4-3-3").
class _FormationLabels extends StatelessWidget {
  const _FormationLabels({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (detail.homeFormation == null && detail.awayFormation == null) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant);
    return Row(
      children: [
        Expanded(child: Text(detail.homeFormation ?? '', style: style)),
        Text('Startelf', style: style),
        Expanded(
          child: Text(detail.awayFormation ?? '',
              textAlign: TextAlign.end, style: style),
        ),
      ],
    );
  }
}

/// Startelf beider Teams auf einem Fußballfeld (Heim unten, Auswärts oben),
/// positioniert nach dem Formationsraster; gelbe/rote Karten am Spieler.
class _PitchLineup extends StatelessWidget {
  const _PitchLineup({
    required this.home,
    required this.away,
    required this.yellow,
    required this.red,
  });

  final List<LineupPlayer> home;
  final List<LineupPlayer> away;
  final Set<int> yellow;
  final Set<int> red;

  List<Widget> _place(List<LineupPlayer> players, bool isHome) {
    final rows = <int, List<LineupPlayer>>{};
    for (final p in players) {
      rows.putIfAbsent(p.row ?? 1, () => []).add(p);
    }
    final keys = rows.keys.toList()..sort();
    final maxRow = keys.isEmpty ? 1 : keys.last;
    final out = <Widget>[];
    for (final r in keys) {
      final line = rows[r]!..sort((a, b) => (a.col ?? 0).compareTo(b.col ?? 0));
      final n = line.length;
      final double yf = maxRow <= 1
          ? (isHome ? 0.9 : 0.1)
          : (isHome
              ? 0.94 - (r - 1) / (maxRow - 1) * (0.94 - 0.56)
              : 0.06 + (r - 1) / (maxRow - 1) * (0.44 - 0.06));
      for (var i = 0; i < n; i++) {
        final p = line[i];
        final xf = (i + 1) / (n + 1);
        final card = p.playerId != null && red.contains(p.playerId)
            ? MatchUpColors.red
            : (p.playerId != null && yellow.contains(p.playerId)
                ? const Color(0xFFFFC83D)
                : null);
        out.add(Align(
          alignment: Alignment(xf * 2 - 1, yf * 2 - 1),
          child: _PlayerMarker(player: p, isHome: isHome, card: card),
        ));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.68,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF1F7A3D), Color(0xFF176230)],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
              ..._place(home, true),
              ..._place(away, false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kurzname (Nachname) für die Anzeige am Feld.
String _shortName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.isEmpty ? name : parts.last;
}

class _PlayerMarker extends StatelessWidget {
  const _PlayerMarker(
      {required this.player, required this.isHome, this.card});
  final LineupPlayer player;
  final bool isHome;
  final Color? card;

  @override
  Widget build(BuildContext context) {
    final ring = isHome ? MatchUpColors.green : const Color(0xFF5B9DF9);
    return SizedBox(
      width: 62,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF12141C),
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: Text('${player.number ?? ''}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ),
              if (card != null)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 9,
                    height: 12,
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.black26, width: 0.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _shortName(player.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Zeichnet die Feldmarkierungen (Außenlinie, Mittellinie, Mittelkreis,
/// Strafräume).
class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final w = size.width, h = size.height;
    final m = w * 0.04;
    final rect = Rect.fromLTRB(m, m, w - m, h - m);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), line);
    // Mittellinie + Mittelkreis.
    canvas.drawLine(Offset(m, h / 2), Offset(w - m, h / 2), line);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, line);
    canvas.drawCircle(Offset(w / 2, h / 2), 2, line..style = PaintingStyle.fill);
    line.style = PaintingStyle.stroke;
    // Strafräume oben und unten.
    final boxW = w * 0.44, boxH = h * 0.14;
    canvas.drawRect(
        Rect.fromLTWH((w - boxW) / 2, m, boxW, boxH), line);
    canvas.drawRect(
        Rect.fromLTWH((w - boxW) / 2, h - m - boxH, boxW, boxH), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LineupBlock extends StatelessWidget {
  const _LineupBlock(
      {required this.title, required this.home, required this.away});
  final String title;
  final List<LineupPlayer> home;
  final List<LineupPlayer> away;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (home.isEmpty && away.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold, color: scheme.primary)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PlayerList(players: home, alignEnd: false)),
            const SizedBox(width: 12),
            Expanded(child: _PlayerList(players: away, alignEnd: true)),
          ],
        ),
      ],
    );
  }
}

class _PlayerList extends StatelessWidget {
  const _PlayerList({required this.players, required this.alignEnd});
  final List<LineupPlayer> players;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget number(int? n) => SizedBox(
          width: 22,
          child: Text(n?.toString() ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)),
        );
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final p in players)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: alignEnd
                  ? [
                      Expanded(
                          child: Text(p.name,
                              textAlign: TextAlign.end,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      number(p.number),
                    ]
                  : [
                      number(p.number),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Statistik
// ---------------------------------------------------------------------
class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.detail});
  final MatchDetail detail;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [for (final s in detail.stats) _StatRow(stat: s)],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stat});
  final MatchStat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = (stat.home + stat.away).toDouble();
    final homeFrac = total <= 0 ? 0.5 : stat.home / total;
    // Mehr = grün, weniger = rot, gleich = neutral.
    final neutral = scheme.onSurfaceVariant;
    final homeColor = stat.home > stat.away
        ? MatchUpColors.green
        : (stat.home < stat.away ? MatchUpColors.red : neutral);
    final awayColor = stat.away > stat.home
        ? MatchUpColors.green
        : (stat.away < stat.home ? MatchUpColors.red : neutral);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('${stat.home}',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: homeColor)),
              Expanded(
                child: Text(stat.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
              Text('${stat.away}',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, color: awayColor)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Row(
              children: [
                Expanded(
                  flex: (homeFrac * 1000).round().clamp(1, 999),
                  child: Container(height: 6, color: homeColor),
                ),
                const SizedBox(width: 2),
                Expanded(
                  flex: ((1 - homeFrac) * 1000).round().clamp(1, 999),
                  child: Container(height: 6, color: awayColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// (Live-)Tabelle
// ---------------------------------------------------------------------
class _TableTab extends ConsumerWidget {
  const _TableTab({required this.leagueId, required this.detail});
  final String leagueId;
  final MatchDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leagueTableProvider(leagueId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Tabelle konnte nicht geladen werden.',
              textAlign: TextAlign.center),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return const Center(child: Text('Noch keine Tabelle verfügbar.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
          itemCount: rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) return const _TableHeader();
            final row = rows[i - 1];
            final highlight =
                row.team.id == detail.home.id || row.team.id == detail.away.id;
            return _TableRow(row: row, highlight: highlight);
          },
        );
      },
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text('#', style: style)),
          const SizedBox(width: 8),
          Expanded(child: Text('Team', style: style)),
          SizedBox(
              width: 30,
              child: Text('Sp', style: style, textAlign: TextAlign.center)),
          SizedBox(
              width: 40,
              child: Text('Diff', style: style, textAlign: TextAlign.center)),
          SizedBox(
              width: 34,
              child: Text('Pkt', style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.row, required this.highlight});
  final StandingRow row;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final diff = row.goalDiff;
    return Container(
      decoration: highlight
          ? BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text('${row.rank}',
                style: TextStyle(
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          TeamBadge(team: row.team),
          const SizedBox(width: 8),
          Expanded(
            child: Text(row.team.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight:
                        highlight ? FontWeight.bold : FontWeight.normal)),
          ),
          SizedBox(
              width: 30,
              child: Text('${row.played}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant))),
          SizedBox(
              width: 40,
              child: Text(diff > 0 ? '+$diff' : '$diff',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant))),
          SizedBox(
              width: 34,
              child: Text('${row.points}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}
