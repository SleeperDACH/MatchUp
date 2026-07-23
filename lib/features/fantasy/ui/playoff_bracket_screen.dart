import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/bracket.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/playoff.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Playoff-Bracket einer Fantasy-Liga: Winner-Bracket (Plätze 1 …) und
/// Loser-/Trost-Bracket (restliche Abschlussplätze) plus die Endtabelle.
/// Setzung = Endstand der regulären Saison; Ergebnisse = effektive
/// Head-to-Head-Punkte der Playoff-Spieltage (clientseitig abgeleitet).
class PlayoffBracketScreen extends ConsumerWidget {
  const PlayoffBracketScreen({super.key, required this.league});

  final FantasyLeague league;

  static const _gold = Color(0xFFFFC83D);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final seasonStatsAsync = ref.watch(seasonStatsProvider);
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;

    Widget scaffold(Widget body) => Scaffold(
          appBar: AppBar(title: const Text('Playoff-Bracket')),
          body: body,
        );

    if (!league.hasPlayoffs) {
      return scaffold(const _Hint(
          'Für diese Liga sind noch keine Playoffs konfiguriert. Das lässt '
          'sich in den Liga-Einstellungen anpassen.'));
    }
    if (managersAsync.isLoading || poolAsync.isLoading) {
      return scaffold(const Center(child: CircularProgressIndicator()));
    }
    final managers = managersAsync.valueOrNull ?? const <FantasyManager>[];
    if (managers.length < 2) {
      return scaffold(const _Hint(
          'Der Bracket braucht mindestens zwei Teams. Teile den '
          'Einladungscode, um die Liga zu füllen.'));
    }
    final pool = poolAsync.valueOrNull ?? const <FantasyPlayer>[];
    final playerById = {for (final p in pool) p.id: p};
    final seasonStats = seasonStatsAsync.valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};

    // Stabile Reihenfolge (Draft-Position) für den Round-Robin der Bilanz.
    final ids = managers.map((m) => m.userId).toList()
      ..sort((a, b) {
        final ma = managers.firstWhere((m) => m.userId == a);
        final mb = managers.firstWhere((m) => m.userId == b);
        final pa = ma.draftPosition ?? 1 << 30;
        final pb = mb.draftPosition ?? 1 << 30;
        return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
      });
    final nameOf = {for (final m in managers) m.userId: m.display};
    final avatarOf = {
      for (final m in managers)
        m.userId: (url: m.avatarUrl, emoji: m.avatarEmoji, color: m.avatarColor)
    };

    // Effektive H2H-Punkte je gewertetem Spieltag.
    final totalsByRound = <int, Map<String, int>>{
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

    final plan = computePlayoffPlan(
      teams: league.playoffTeams!,
      weeksPerRound: league.playoffWeeks ?? 1,
      tradeDeadlineOffset: league.tradeDeadlineOffset ?? 5,
      totalTeams: managers.length,
    );

    // Setzung: Endstand der regulären Saison (nur Spieltage vor Playoff-Start).
    final regularTotals = {
      for (final e in totalsByRound.entries)
        if (e.key < plan.startRound) e.key: e.value
    };
    final seeding = [
      for (final r in h2hStandings(ids, regularTotals)) r.managerId
    ];

    // Abgeschlossene Spieltage (alle Spiele beendet).
    final finished = <int>{};
    final byMd = <int, List<Fixture>>{};
    for (final f in allFx) {
      (byMd[f.round] ??= []).add(f);
    }
    byMd.forEach((md, fx) {
      if (fx.isNotEmpty && fx.every((f) => f.status == FixtureStatus.finished)) {
        finished.add(md);
      }
    });

    final bracket = buildPlayoffBracket(
      seeding: seeding,
      playoffTeams: league.playoffTeams!,
      startRound: plan.startRound,
      weeksPerRound: plan.weeksPerRound,
      roundTotals: totalsByRound,
      finishedMatchdays: finished,
    );

    return scaffold(ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        _PlanBanner(plan: plan, gold: _gold),
        const SizedBox(height: 12),
        if (bracket.complete) ...[
          _SectionHeader(
              icon: Icons.emoji_events, title: 'Endplatzierung', color: _gold),
          for (final p in bracket.placements)
            _PlacementRow(
              place: p.place,
              name: nameOf[p.managerId] ?? '?',
              avatar: avatarOf[p.managerId],
              me: p.managerId == myId,
              playoff: p.place <= bracket.playoffTeams,
            ),
          const SizedBox(height: 16),
        ],
        _SectionHeader(
            icon: Icons.account_tree, title: 'Winner-Bracket', color: _gold),
        _Legend(text: 'Plätze 1–${bracket.playoffTeams} · Setzung aus der Tabelle'),
        for (final r in bracket.winners)
          _RoundBlock(
              round: r,
              nameOf: nameOf,
              avatarOf: avatarOf,
              myId: myId,
              accent: _gold),
        if (bracket.consolation.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionHeader(
              icon: Icons.shield_moon_outlined,
              title: 'Loser-Bracket',
              color: scheme.onSurfaceVariant),
          _Legend(
              text: 'Plätze ${bracket.playoffTeams + 1}–${bracket.placements.length}'
                  ' · restliche Abschlussplätze'),
          for (final r in bracket.consolation)
            _RoundBlock(
                round: r,
                nameOf: nameOf,
                avatarOf: avatarOf,
                myId: myId,
                accent: scheme.onSurfaceVariant),
        ],
        const SizedBox(height: 12),
        _Hint(
          bracket.complete
              ? 'Alle Plätze ausgespielt.'
              : 'Setzung aus dem Endstand der regulären Saison. Ergebnisse und '
                  'Platzierungen stehen fest, sobald die jeweiligen '
                  'Playoff-Spieltage beendet sind.',
        ),
      ],
    ));
  }
}

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({required this.plan, required this.gold});
  final PlayoffPlan plan;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: gold.withValues(alpha: 0.12),
        border: Border.all(color: gold.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: gold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Playoffs ab Spieltag ${plan.startRound}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  '${plan.rounds} Runden × '
                  '${plan.weeksPerRound == 2 ? '2 Wochen' : '1 Woche'} · '
                  'Trade-Deadline Spieltag ${plan.tradeDeadlineRound}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon, required this.title, required this.color});
  final IconData icon;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _RoundBlock extends StatelessWidget {
  const _RoundBlock({
    required this.round,
    required this.nameOf,
    required this.avatarOf,
    required this.myId,
    required this.accent,
  });

  final BracketRound round;
  final Map<String, String> nameOf;
  final Map<String, ({String? url, String? emoji, String? color})> avatarOf;
  final String? myId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (round.matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in round.matches)
          _MatchCard(
              match: m,
              nameOf: nameOf,
              avatarOf: avatarOf,
              myId: myId,
              accent: accent),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.nameOf,
    required this.avatarOf,
    required this.myId,
    required this.accent,
  });

  final BracketMatch match;
  final Map<String, String> nameOf;
  final Map<String, ({String? url, String? emoji, String? color})> avatarOf;
  final String? myId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(match.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: accent)),
                const Spacer(),
                _StatusChip(match: match),
              ],
            ),
            const SizedBox(height: 6),
            _SideRow(
                slot: match.home,
                points: match.homePoints,
                winner: match.decided && match.winnerId == match.home.managerId,
                nameOf: nameOf,
                avatarOf: avatarOf,
                myId: myId),
            const SizedBox(height: 4),
            _SideRow(
                slot: match.away,
                points: match.awayPoints,
                winner: match.decided && match.winnerId == match.away.managerId,
                nameOf: nameOf,
                avatarOf: avatarOf,
                myId: myId),
          ],
        ),
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.slot,
    required this.points,
    required this.winner,
    required this.nameOf,
    required this.avatarOf,
    required this.myId,
  });

  final BracketSlot slot;
  final int points;
  final bool winner;
  final Map<String, String> nameOf;
  final Map<String, ({String? url, String? emoji, String? color})> avatarOf;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = slot.managerId;
    final label = slot.isBye
        ? 'Freilos'
        : (id == null ? 'steht noch aus' : (nameOf[id] ?? '?'));
    final av = id == null ? null : avatarOf[id];
    final me = id != null && id == myId;
    return Row(
      children: [
        if (slot.seed != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text('${slot.seed}',
                style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold)),
          ),
        AppAvatar(
          imageUrl: av?.url,
          emoji: av?.emoji,
          colorHex: av?.color,
          fallbackText: id == null ? null : label,
          fallbackIcon: id == null ? Icons.remove : null,
          size: 26,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: winner || me ? FontWeight.bold : FontWeight.normal,
                color: slot.managerId == null
                    ? scheme.onSurfaceVariant
                    : null,
              )),
        ),
        if (winner)
          const Padding(
            padding: EdgeInsets.only(right: 6),
            child: Icon(Icons.check_circle, size: 16, color: Color(0xFF4ADE6A)),
          ),
        if (slot.managerId != null)
          Text('$points',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: winner ? scheme.onSurface : scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.match});
  final BracketMatch match;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final String text;
    late final Color color;
    if (match.decided) {
      text = 'beendet';
      color = scheme.onSurfaceVariant;
    } else if (match.isLive) {
      text = 'live';
      color = const Color(0xFFF23030);
    } else {
      text = 'Spieltag ${match.startMatchday}'
          '${match.weeks == 2 ? '–${match.startMatchday + 1}' : ''}';
      color = scheme.onSurfaceVariant;
    }
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.bold));
  }
}

class _PlacementRow extends StatelessWidget {
  const _PlacementRow({
    required this.place,
    required this.name,
    required this.me,
    required this.playoff,
    this.avatar,
  });

  final int place;
  final String name;
  final ({String? url, String? emoji, String? color})? avatar;
  final bool me;
  final bool playoff;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (place) {
      1 => (const Color(0xFFFFC83D), Colors.black),
      2 => (const Color(0xFFC4CBD4), Colors.black),
      3 => (const Color(0xFFCD8B4E), Colors.white),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: me
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: me
            ? Border.all(color: scheme.primary.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Text('$place',
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          AppAvatar(
            imageUrl: avatar?.url,
            emoji: avatar?.emoji,
            colorHex: avatar?.color,
            fallbackText: name,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: me ? FontWeight.bold : FontWeight.w600)),
          ),
          if (!playoff)
            Text('Trost',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
