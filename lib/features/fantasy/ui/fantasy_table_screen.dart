import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'manager_profile_screen.dart';
import 'playoff_bracket_screen.dart';
import 'weekly_recap_screen.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [FantasyTableBody].
class FantasyTableScreen extends StatelessWidget {
  const FantasyTableScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Liga-Tabelle')),
      body: FantasyTableBody(league: league),
    );
  }
}

/// Liga-Tabelle nach **Head-to-Head-Bilanz**: pro Spieltag ein 1-gegen-1
/// (effektive Startelf), gewertet als Sieg / Unentschieden / Niederlage.
/// Sortiert nach Siegen, dann Punktedifferenz. Body ohne Scaffold, damit er
/// als Tab einsetzbar ist.
class FantasyTableBody extends ConsumerStatefulWidget {
  const FantasyTableBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<FantasyTableBody> createState() => _FantasyTableBodyState();
}

class _FantasyTableBodyState extends ConsumerState<FantasyTableBody> {
  /// Gewählter Spieltag im Rückblick; `null` = der zuletzt abgepfiffene.
  int? _rueckblick;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final seasonStatsAsync = ref.watch(seasonStatsProvider);
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final myId = ref.watch(currentUserProvider)?.id;

    if (managersAsync.isLoading || poolAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final managers = managersAsync.requireValue;
    final pool = poolAsync.requireValue;
    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.display};
    final avatarOf = {
      for (final m in managers)
        m.userId: (url: m.avatarUrl, emoji: m.avatarEmoji, color: m.avatarColor)
    };
    final seasonStats = seasonStatsAsync.valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    if (managers.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Die Tabelle braucht mindestens zwei Manager.',
              textAlign: TextAlign.center),
        ),
      );
    }

    // Stabile Reihenfolge (Draft-Position, dann User-ID) für den Round-Robin.
    final ids = managers.map((m) => m.userId).toList()
      ..sort((a, b) {
        final ma = managers.firstWhere((m) => m.userId == a);
        final mb = managers.firstWhere((m) => m.userId == b);
        final pa = ma.draftPosition ?? 1 << 30;
        final pb = mb.draftPosition ?? 1 << 30;
        return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
      });

    final totalsByRound = <int, Map<String, double>>{
      for (final entry in seasonStats.entries)
        entry.key: effectiveTotalsForRound(
          stats: entry.value,
          round: entry.key,
          managers: managers,
          roster: roster,
          playerById: playerById,
          lineups: lineups,
          scoring: league.scoring,
          rosterConfig: league.roster,
        )
    };
    final standings = h2hStandings(ids, totalsByRound);
    final nonePlayed = standings.every((r) => r.played == 0);

    final abgepfiffen = ref.watch(abgepfiffeneRundenProvider);
    final rueckblick =
        _rueckblick ?? (abgepfiffen.isEmpty ? null : abgepfiffen.last);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (seasonStatsAsync.isLoading)
          const LinearProgressIndicator(minHeight: 2),
        if (league.hasPlayoffs) _BracketButton(league: league),
        const _Marke('Tabelle'),
        if (nonePlayed)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              'Noch keine gewerteten Spieltage — die Bilanz startet bei 0.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        // **Kopfzeile statt Erklärabsatz.** Vorher stand unter der Tabelle ein
        // fünfzeiliger Text, der erklärte, wofür S, U, N und „erzielt" stehen —
        // an der Stelle, an der ihn niemand liest. Jetzt steht es über den
        // Spalten, wo es hingehört.
        const _TabellenKopf(),
        // Die Bilanzen sind **eine** Tabelle, nicht vier Kästen. Vorher trug
        // jede Zeile eigene Ränder, Ecken und Fläche; vier gleich laute
        // Objekte untereinander lesen sich nicht als Rangfolge.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, r) in standings.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.07),
                    ),
                  _RecordRow(
                    rank: i + 1,
                    name: nameOf[r.managerId] ?? '?',
                    avatar: avatarOf[r.managerId],
                    record: r,
                    me: r.managerId == myId,
                    onTap: () => showManagerProfile(context,
                        league: league,
                        managerId: r.managerId,
                        managerName: nameOf[r.managerId] ?? '?'),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Text(
            'Je Spieltag ein Duell mit der effektiven Startelf — 3 Punkte für '
            'einen Sieg, 1 für ein Unentschieden. Bei Gleichstand zählen die '
            'erzielten Spielerpunkte.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),

        // --- Rückblick -----------------------------------------------------
        // Der Wochen-Recap wohnt hier, nicht mehr nur auf der Übersicht: Dort
        // zeigte er allein den laufenden Spieltag, und wer auf eine frühere
        // Woche zurückwollte, hatte keinen Weg dorthin.
        if (abgepfiffen.isNotEmpty && rueckblick != null) ...[
          const _Marke('Rückblick'),
          _SpieltagWahl(
            runden: abgepfiffen,
            gewaehlt: rueckblick,
            onWahl: (r) => setState(() => _rueckblick = r),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: WeeklyRecapCard(league: league, runde: rueckblick),
          ),
        ],
      ],
    );
  }
}

/// Kapitelmarke: farbiger Strich, Wort, Haarlinie bis an den Rand — dieselbe
/// Gliederung wie auf dem Startbildschirm und im Live-Tab.
class _Marke extends StatelessWidget {
  const _Marke(this.wort);

  final String wort;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Row(
        children: [
          Container(width: 3, height: 12, color: scheme.primary),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: Text(
              wort.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

/// Spaltenköpfe der Tabelle.
///
/// Die Breiten müssen zu [_RecordRow] passen — sie stehen deshalb als
/// Konstanten an einer Stelle, nicht zweimal als Zahl im Layout.
class _TabellenKopf extends StatelessWidget {
  const _TabellenKopf();

  static const rangBreite = 30.0;
  static const bilanzBreite = 74.0;
  static const punkteBreite = 52.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stil = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: scheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
      child: Row(
        children: [
          SizedBox(width: rangBreite, child: Text('#', style: stil)),
          const SizedBox(width: 10),
          Expanded(child: Text('TEAM', style: stil)),
          SizedBox(
            width: bilanzBreite,
            child: Text('S · U · N', style: stil, textAlign: TextAlign.end),
          ),
          SizedBox(
            width: punkteBreite,
            child: Text('PUNKTE', style: stil, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Spieltagswahl im Rückblick: ‹ Spieltag N ›.
///
/// Die Pfeile nennen ihr **Ziel**, nicht ihre Richtung — dieselbe Regel wie
/// bei den übrigen Blätter-Pfeilen der App: Vorgelesen sagt „Zurück" allein
/// nicht, wohin es geht.
class _SpieltagWahl extends StatelessWidget {
  const _SpieltagWahl({
    required this.runden,
    required this.gewaehlt,
    required this.onWahl,
  });

  final List<int> runden;
  final int gewaehlt;
  final ValueChanged<int> onWahl;

  @override
  Widget build(BuildContext context) {
    final i = runden.indexOf(gewaehlt);
    // `runden` ist aufsteigend: links geht es zum **früheren** Spieltag.
    final frueher = i > 0 ? runden[i - 1] : null;
    final spaeter = i >= 0 && i < runden.length - 1 ? runden[i + 1] : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip:
                frueher == null ? 'Zurück' : 'Zurück zu Spieltag $frueher',
            onPressed: frueher == null ? null : () => onWahl(frueher),
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Spieltag $gewaehlt',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(
            tooltip:
                spaeter == null ? 'Weiter' : 'Weiter zu Spieltag $spaeter',
            onPressed: spaeter == null ? null : () => onWahl(spaeter),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

/// Einstieg zum Playoff-Bracket (Winner- + Loser-Bracket, Endplatzierung).
class _BracketButton extends StatelessWidget {
  const _BracketButton({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFFFC83D);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Material(
        color: gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayoffBracketScreen(league: league))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.account_tree, color: gold),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Playoff-Bracket',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'Winner- & Loser-Bracket — alle Abschlussplätze',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({
    required this.rank,
    required this.name,
    required this.record,
    required this.me,
    required this.onTap,
    this.avatar,
  });

  final int rank;
  final String name;
  final AvatarInfo? avatar;
  final H2HRecord record;
  final bool me;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (badgeBg, badgeFg) = _rankColors(rank, scheme);

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      // Die eigene Zeile bekommt nur eine getönte Fläche, keinen Rahmen: In
      // einer Tabelle, die als **eine** Fläche steht, wäre ein Rahmen um eine
      // Zeile ein Kasten im Kasten.
      color: me ? scheme.primary.withValues(alpha: 0.10) : null,
      child: Row(
        children: [
          // Rang (Top 3 in Medaillenfarben).
          Container(
            width: _TabellenKopf.rangBreite,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$rank',
                style: TextStyle(
                    color: badgeFg,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          const SizedBox(width: 10),
          AppAvatar(
            imageUrl: avatar?.url,
            emoji: avatar?.emoji,
            colorHex: avatar?.color,
            fallbackText: name,
            size: 28,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: me ? FontWeight.w800 : FontWeight.w600)),
          ),
          // Bilanz in ihrer eigenen Spalte — sie stand vorher als Kleintext
          // unter dem Namen und fluchtete mit nichts.
          SizedBox(
            width: _TabellenKopf.bilanzBreite,
            child: Text(
              '${record.wins} · ${record.ties} · ${record.losses}',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Rechts: Tabellenpunkte groß, darunter die erzielten
          // Spielerpunkte (Tiebreak). Feste Spaltenbreite, damit die Zahlen
          // über alle Zeilen fluchten — vorher rutschte die Spalte je nach
          // Stellenzahl.
          SizedBox(
            width: _TabellenKopf.punkteBreite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${record.points}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        height: 1.1,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Text(formatPoints(record.pointsFor),
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Rang-Badge-Farben: Gold/Silber/Bronze für Top 3, sonst neutral.
  (Color, Color) _rankColors(int rank, ColorScheme scheme) => switch (rank) {
        1 => (const Color(0xFFFFC83D), Colors.black),
        2 => (const Color(0xFFC4CBD4), Colors.black),
        3 => (const Color(0xFFCD8B4E), Colors.white),
        _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      };
}
