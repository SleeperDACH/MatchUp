import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/weekly_recap.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'manager_profile_screen.dart';
import 'matchday_stepper.dart';
import 'player_profile_sheet.dart';

// Award-Palette (abgestimmt auf die MatchUp-Übersicht).
const _cGold = Color(0xFFFFC83D);
const _cStar = Color(0xFFF2A63B);
const _cTeal = Color(0xFF4FC3A1);
const _cBlue = Color(0xFF5B9DF9);
const _cRed = Color(0xFFF23030);
const _cViolet = Color(0xFF9B7BE0);
const _cGrey = Color(0xFF8A8F9C);

/// Öffnet das Wochen-Recap einer Liga (optional für einen bestimmten Spieltag).
void showWeeklyRecap(BuildContext context,
    {required FantasyLeague league, int? round}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => WeeklyRecapScreen(league: league, initialRound: round),
  ));
}

/// Stabile Manager-Reihenfolge wie im MatchUp-Tab (Draft-Position, dann ID).
List<String> stableManagerIds(List<FantasyManager> managers) {
  final ids = managers.map((m) => m.userId).toList();
  final posOf = {for (final m in managers) m.userId: m.draftPosition ?? 1 << 30};
  ids.sort((a, b) {
    final pa = posOf[a]!;
    final pb = posOf[b]!;
    return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
  });
  return ids;
}

/// Wochen-Recap-Screen: pro Spieltag die „Sleeper-Awards" (Team der Woche,
/// MVP, Bank-Held, Nervenkrimi, Klatsche, vergeigte Bank, Griff ins Klo).
/// Standard-Spieltag ist der aktuelle; über den Stepper navigierbar.
class WeeklyRecapScreen extends ConsumerStatefulWidget {
  const WeeklyRecapScreen({super.key, required this.league, this.initialRound});

  final FantasyLeague league;
  final int? initialRound;

  @override
  ConsumerState<WeeklyRecapScreen> createState() => _WeeklyRecapScreenState();
}

class _WeeklyRecapScreenState extends ConsumerState<WeeklyRecapScreen> {
  int? _round;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? widget.initialRound ?? current ?? 1;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final stats = statsAsync.valueOrNull ?? const <String, PlayerMatchStats>{};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Wochen-Recap')),
      body: (managersAsync.isLoading || poolAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final managers = managersAsync.requireValue;
              final pool = poolAsync.requireValue;
              final playerById = {for (final p in pool) p.id: p};
              final nameOf = {for (final m in managers) m.userId: m.username};
              final ids = stableManagerIds(managers);

              final roundFx = [for (final f in allFx) if (f.round == round) f];
              final live = roundFx.isNotEmpty &&
                  roundFx.any((f) => f.status != FixtureStatus.finished) &&
                  roundFx.any((f) => f.status != FixtureStatus.scheduled);
              final started = roundFx.isNotEmpty &&
                  roundFx.any((f) => f.status != FixtureStatus.scheduled);

              final recap = computeWeeklyRecap(
                round: round,
                ids: ids,
                roster: roster,
                playerById: playerById,
                lineups: lineups,
                stats: stats,
                scoring: league.scoring,
                rosterConfig: league.roster,
              );

              void openManager(String id) => showManagerProfile(context,
                  league: league, managerId: id, managerName: nameOf[id] ?? '?');
              void openPlayer(String playerId, bool mine) {
                final p = playerById[playerId];
                if (p == null) return;
                showPlayerProfile(context,
                    league: league,
                    player: p,
                    clubIcon: clubIcons[p.club],
                    isMine: mine);
              }

              return ListView(
                children: [
                  MatchdayStepper(
                      round: round,
                      onChanged: (r) => setState(() => _round = r)),
                  if (statsAsync.isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  _StatusLine(live: live, started: started),
                  if (ids.length < 2)
                    const _EmptyHint(
                        'Ein Recap braucht mindestens zwei Manager.')
                  else if (!recap.hasData)
                    _EmptyHint(started
                        ? 'Für diesen Spieltag liegen noch keine gewerteten '
                            'Punkte vor.'
                        : 'Spieltag $round hat noch nicht begonnen.')
                  else
                    ..._awards(
                      context,
                      recap: recap,
                      nameOf: nameOf,
                      playerById: playerById,
                      clubIcons: clubIcons,
                      myId: myId,
                      onManager: openManager,
                      onPlayer: openPlayer,
                    ),
                  const SizedBox(height: 24),
                ],
              );
            }),
    );
  }

  List<Widget> _awards(
    BuildContext context, {
    required WeeklyRecap recap,
    required Map<String, String> nameOf,
    required Map<String, FantasyPlayer> playerById,
    required Map<String, String?> clubIcons,
    required String? myId,
    required void Function(String) onManager,
    required void Function(String, bool) onPlayer,
  }) {
    String name(String id) => nameOf[id] ?? '?';
    final cards = <Widget>[];

    void managerAward({
      required Color color,
      required IconData icon,
      required String title,
      required String managerId,
      required int points,
      String? suffix,
    }) {
      cards.add(_AwardCard(
        color: color,
        icon: icon,
        title: title,
        primary: name(managerId),
        secondary: suffix,
        value: '$points',
        valueLabel: 'Pkt',
        highlight: managerId == myId,
        onTap: () => onManager(managerId),
      ));
    }

    void playerAward({
      required Color color,
      required IconData icon,
      required String title,
      required PlayerAward award,
    }) {
      final p = playerById[award.playerId];
      cards.add(_AwardCard(
        color: color,
        icon: icon,
        title: title,
        primary: p?.name ?? '?',
        secondary: 'Kader: ${name(award.managerId)}',
        value: '${award.points}',
        valueLabel: 'Pkt',
        highlight: award.managerId == myId,
        badge: p == null
            ? null
            : ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 34),
        onTap: () => onPlayer(award.playerId, award.managerId == myId),
      ));
    }

    if (recap.topScore != null) {
      managerAward(
        color: _cGold,
        icon: Icons.emoji_events,
        title: 'Team der Woche',
        managerId: recap.topScore!.managerId,
        points: recap.topScore!.points,
        suffix: 'Höchstes Ergebnis des Spieltags',
      );
    }
    if (recap.mvp != null) {
      playerAward(
        color: _cStar,
        icon: Icons.star,
        title: 'MVP der Woche',
        award: recap.mvp!,
      );
    }
    if (recap.benchHero != null) {
      playerAward(
        color: _cTeal,
        icon: Icons.event_seat,
        title: 'Bank-Held',
        award: recap.benchHero!,
      );
    }
    if (recap.closestWin != null) {
      final m = recap.closestWin!;
      cards.add(_AwardCard(
        color: _cBlue,
        icon: Icons.bolt,
        title: 'Nervenkrimi',
        primary: name(m.winnerId),
        secondary: 'schlägt ${name(m.loserId)} · +${m.margin}',
        value: '${m.winnerPoints}:${m.loserPoints}',
        highlight: m.winnerId == myId || m.loserId == myId,
        onTap: () => onManager(m.winnerId),
      ));
    }
    if (recap.blowout != null && recap.blowout!.margin != recap.closestWin?.margin) {
      final m = recap.blowout!;
      cards.add(_AwardCard(
        color: _cRed,
        icon: Icons.local_fire_department,
        title: 'Klatsche',
        primary: name(m.winnerId),
        secondary: 'deklassiert ${name(m.loserId)} · +${m.margin}',
        value: '${m.winnerPoints}:${m.loserPoints}',
        highlight: m.winnerId == myId || m.loserId == myId,
        onTap: () => onManager(m.winnerId),
      ));
    }
    if (recap.benchBlunder != null) {
      managerAward(
        color: _cViolet,
        icon: Icons.sentiment_dissatisfied,
        title: 'Vergeigte Bank',
        managerId: recap.benchBlunder!.managerId,
        points: recap.benchBlunder!.pointsLeft,
        suffix: 'Punkte auf der Bank liegengelassen',
      );
    }
    if (recap.lowScore != null) {
      managerAward(
        color: _cGrey,
        icon: Icons.trending_down,
        title: 'Griff ins Klo',
        managerId: recap.lowScore!.managerId,
        points: recap.lowScore!.points,
        suffix: 'Niedrigstes Ergebnis des Spieltags',
      );
    }
    return cards;
  }
}

/// Status-Zeile unter dem Stepper: LIVE / Beendet / Vorschau.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.live, required this.started});

  final bool live;
  final bool started;

  @override
  Widget build(BuildContext context) {
    final (color, label) = live
        ? (_cRed, 'LIVE')
        : started
            ? (_cTeal, 'Beendet')
            : (_cGrey, 'Vorschau');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
      child: Text(text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

/// Eine Award-Karte: farbiges Symbol, Titel + Träger, große Kennzahl rechts.
class _AwardCard extends StatelessWidget {
  const _AwardCard({
    required this.color,
    required this.icon,
    required this.title,
    required this.primary,
    required this.value,
    this.secondary,
    this.valueLabel,
    this.highlight = false,
    this.badge,
    this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String primary;
  final String? secondary;
  final String value;
  final String? valueLabel;
  final bool highlight;
  final Widget? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: highlight
            ? color.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: highlight ? 0.6 : 0.28),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.toUpperCase(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 2),
                      Text(primary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      if (secondary != null)
                        Text(secondary!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 8),
                  badge!,
                ],
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold, color: color)),
                    if (valueLabel != null)
                      Text(valueLabel!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kompakte Recap-Kachel für die Übersicht: zeigt das aktuelle Team der
/// Woche + MVP und öffnet auf Tippen das volle Recap. Rendert nichts, solange
/// es für den aktuellen Spieltag keine gewerteten Punkte gibt.
class WeeklyRecapCard extends ConsumerWidget {
  const WeeklyRecapCard({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    if (current == null) return const SizedBox.shrink();

    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    if (managers == null || pool == null || managers.length < 2) {
      return const SizedBox.shrink();
    }
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final stats = ref.watch(roundStatsProvider(current)).valueOrNull ??
        const <String, PlayerMatchStats>{};

    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.username};
    final recap = computeWeeklyRecap(
      round: current,
      ids: stableManagerIds(managers),
      roster: roster,
      playerById: playerById,
      lineups: lineups,
      stats: stats,
      scoring: league.scoring,
      rosterConfig: league.roster,
    );
    if (!recap.hasData) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final top = recap.topScore;
    final mvp = recap.mvp;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
      color: _cGold.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => showWeeklyRecap(context, league: league, round: current),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cGold.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events, color: _cGold, size: 18),
                  const SizedBox(width: 6),
                  Text('RECAP · SPIELTAG ${recap.round}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _cGold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 10),
              if (top != null)
                _MiniLine(
                  label: 'Team der Woche',
                  value: nameOf[top.managerId] ?? '?',
                  trailing: '${top.points} Pkt',
                ),
              if (mvp != null) ...[
                const SizedBox(height: 4),
                _MiniLine(
                  label: 'MVP',
                  value: playerById[mvp.playerId]?.name ?? '?',
                  trailing: '${mvp.points} Pkt',
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  const _MiniLine(
      {required this.label, required this.value, required this.trailing});

  final String label;
  final String value;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 116,
          child: Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Text(trailing,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
