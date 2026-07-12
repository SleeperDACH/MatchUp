import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/round_table.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'tip_member_profile_sheet.dart';

/// Head-to-Head-Modus einer Tipprunde: jeder Spieltag als Duell zwischen zwei
/// Mitgliedern. Die Punkte je Spieltag kommen aus der normalen Tipp-Wertung
/// ([totalPointsByMember]); der Spielplan ist der deterministische Round-Robin
/// aus [roundPairings]. Darunter die Saison-Bilanz (Siege-Niederlagen-Remis).
class TipDuelsTab extends ConsumerStatefulWidget {
  const TipDuelsTab({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<TipDuelsTab> createState() => _TipDuelsTabState();
}

class _TipDuelsTabState extends ConsumerState<TipDuelsTab> {
  int? _spieltag;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final rules = round.scoring;

    final membersAsync = ref.watch(roundMembersProvider(round.id));
    final fixturesAsync =
        ref.watch(leagueSeasonFixturesProvider(round.leagueId));
    final tips =
        ref.watch(allRoundTipsProvider(round.id)).valueOrNull ?? const [];
    final frozen = ref.watch(frozenOddsProvider).valueOrNull ??
        const <String, FrozenOdds>{};
    final current = ref.watch(currentRoundProvider).valueOrNull;

    if (membersAsync.isLoading || fixturesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final members = membersAsync.valueOrNull ?? const <RoundMember>[];
    final fixtures = fixturesAsync.valueOrNull ?? const <Fixture>[];

    if (members.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Duelle brauchen mindestens zwei Mitglieder.',
              textAlign: TextAlign.center),
        ),
      );
    }

    // Stabile, deterministische Reihenfolge für den Spielplan.
    final ids = members.map((m) => m.userId).toList()..sort();
    final nameOf = {for (final m in members) m.userId: m.display};
    final memberById = {for (final m in members) m.userId: m};

    // Fixtures nach Spieltag gruppieren.
    final byRound = <int, List<Fixture>>{};
    for (final f in fixtures) {
      byRound.putIfAbsent(f.round, () => []).add(f);
    }
    final maxRound =
        byRound.keys.isEmpty ? 1 : byRound.keys.reduce((a, b) => a > b ? a : b);
    final spieltag = (_spieltag ?? current ?? 1).clamp(1, maxRound);

    Map<String, int> totalsFor(List<Fixture> fx) => totalPointsByMember(
          members: members,
          tips: tips,
          fixtures: fx,
          rules: rules,
          frozenOdds: frozen,
        );

    // Bilanz über alle Spieltage mit mindestens einem gewerteten Spiel.
    final totalsByRound = <int, Map<String, int>>{
      for (final e in byRound.entries)
        if (e.value.any((f) => f.hasScore)) e.key: totalsFor(e.value),
    };
    final standings = h2hStandings(ids, totalsByRound);

    // Ausgewählter Spieltag: Punkte + Paarungen.
    final roundFx = byRound[spieltag] ?? const <Fixture>[];
    final started = roundFx.any((f) => f.hasScore);
    final roundTotals = totalsFor(roundFx);
    final pairings = roundPairings(ids, spieltag);
    final myId = ref.watch(currentUserProvider)?.id;

    return ListView(
      children: [
        _Stepper(
          spieltag: spieltag,
          max: maxRound,
          onChanged: (r) => setState(() => _spieltag = r),
        ),
        for (final m in pairings)
          _DuelCard(
            homeName: nameOf[m.home] ?? '?',
            awayName: m.isBye ? null : (nameOf[m.away] ?? '?'),
            homePoints: roundTotals[m.home] ?? 0,
            awayPoints: m.isBye ? 0 : (roundTotals[m.away] ?? 0),
            started: started,
            homeMe: m.home == myId,
            awayMe: m.away == myId,
          ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Bilanz (S-N-U)',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (standings.every((r) => r.played == 0))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Noch keine gewerteten Spieltage.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          )
        else
          for (final (i, r) in standings.indexed)
            _StandingRow(
              rank: i + 1,
              name: nameOf[r.managerId] ?? '?',
              avatar: () {
                final m = memberById[r.managerId];
                return m == null
                    ? null
                    : (url: m.avatarUrl, emoji: m.avatarEmoji, color: m.avatarColor);
              }(),
              record: r,
              me: r.managerId == myId,
              onTap: () {
                final mem = memberById[r.managerId];
                if (mem != null) {
                  showTipMemberProfile(context,
                      round: widget.round, member: mem);
                }
              },
            ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Spieltag-Umschalter (‹ Spieltag N ›).
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.spieltag,
    required this.max,
    required this.onChanged,
  });

  final int spieltag;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: spieltag > 1 ? () => onChanged(spieltag - 1) : null,
          ),
          Text('Spieltag $spieltag',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: spieltag < max ? () => onChanged(spieltag + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Eine Duell-Karte: zwei Mitglieder + ihre Tipp-Punkte des Spieltags.
class _DuelCard extends StatelessWidget {
  const _DuelCard({
    required this.homeName,
    required this.awayName,
    required this.homePoints,
    required this.awayPoints,
    required this.started,
    required this.homeMe,
    required this.awayMe,
  });

  final String homeName;
  final String? awayName; // null = Bye
  final int homePoints;
  final int awayPoints;
  final bool started;
  final bool homeMe;
  final bool awayMe;

  @override
  Widget build(BuildContext context) {
    if (awayName == null) {
      return Card(
        child: ListTile(
          title: Text(homeName,
              style: homeMe ? const TextStyle(fontWeight: FontWeight.bold) : null),
          trailing: Text('spielfrei',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    final homeWin = started && homePoints > awayPoints;
    final awayWin = started && awayPoints > homePoints;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
                child: _side(context, homeName, homeMe, homeWin,
                    align: CrossAxisAlignment.start)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                started ? '$homePoints : $awayPoints' : 'vs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Expanded(
                child: _side(context, awayName!, awayMe, awayWin,
                    align: CrossAxisAlignment.end)),
          ],
        ),
      ),
    );
  }

  Widget _side(BuildContext context, String name, bool me, bool win,
      {required CrossAxisAlignment align}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              align == CrossAxisAlignment.start ? TextAlign.start : TextAlign.end,
          style: TextStyle(
            fontWeight: me || win ? FontWeight.bold : FontWeight.normal,
            color: win ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        if (win)
          Text('Sieg',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary)),
      ],
    );
  }
}

/// Eine Bilanz-Zeile (Rang, Name, erzielte:kassierte Punkte, S-N-U).
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.name,
    required this.record,
    required this.me,
    this.avatar,
    this.onTap,
  });

  final int rank;
  final String name;
  final AvatarInfo? avatar;
  final H2HRecord record;
  final bool me;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: rank == 1
            ? scheme.primary.withValues(alpha: 0.25)
            : scheme.surfaceContainerHighest,
        child: Text('$rank', style: const TextStyle(fontSize: 12)),
      ),
      title: Row(
        children: [
          AppAvatar(
            imageUrl: avatar?.url,
            emoji: avatar?.emoji,
            colorHex: avatar?.color,
            fallbackText: name,
            size: 22,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(name,
                overflow: TextOverflow.ellipsis,
                style:
                    me ? const TextStyle(fontWeight: FontWeight.bold) : null),
          ),
        ],
      ),
      subtitle: Text('${record.pointsFor}:${record.pointsAgainst} Pkt.'),
      trailing: Text(
        '${record.wins}-${record.losses}-${record.ties}',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}
