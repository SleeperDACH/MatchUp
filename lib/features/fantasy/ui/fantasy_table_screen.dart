import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'manager_profile_screen.dart';

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
class FantasyTableBody extends ConsumerWidget {
  const FantasyTableBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final standings = h2hStandings(ids, totalsByRound);
    final nonePlayed = standings.every((r) => r.played == 0);

    return ListView(
      children: [
        if (seasonStatsAsync.isLoading)
          const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 6),
        if (nonePlayed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Text(
              'Noch keine gewerteten Spieltage — die Bilanz startet bei 0.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        // Teilnehmer immer anzeigen (auch mit 0-0-0 vor dem ersten Spieltag).
        for (final (i, r) in standings.indexed)
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
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Bilanz aus Head-to-Head je Spieltag (effektive Startelf). '
            'Sortiert nach Siegen, dann Punktedifferenz. '
            'S = Siege, N = Niederlagen.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: me
            ? scheme.primary.withValues(alpha: 0.14)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: me
            ? Border.all(color: scheme.primary.withValues(alpha: 0.6), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // Rang-Badge (Top 3 in Medaillenfarben).
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badgeBg, shape: BoxShape.circle),
            child: Text('$rank',
                style: TextStyle(
                    color: badgeFg,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
          const SizedBox(width: 10),
          AppAvatar(
            imageUrl: avatar?.url,
            emoji: avatar?.emoji,
            colorHex: avatar?.color,
            fallbackText: name,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: me ? FontWeight.bold : FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          // Record rechts: Siege (grün) : Niederlagen (rot), ohne Buchstaben.
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${record.wins}',
                  style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 24)),
              Text('  :  ',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 16)),
              Text('${record.losses}',
                  style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 24)),
            ],
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
