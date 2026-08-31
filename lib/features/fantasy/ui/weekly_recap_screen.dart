import 'package:flutter/material.dart';

import '../../../app/widgets/karte.dart';
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
import '../logic/kader_am.dart';
import '../models/roster_move.dart';

// Award-Palette (abgestimmt auf die MatchUp-Übersicht).
const _cGold = Color(0xFFFFC83D);
const _cStar = Color(0xFFF2A63B);
const _cTeal = Color(0xFF4FC3A1);
const _cBlue = Color(0xFF5B9DF9);
const _cRed = Color(0xFFF23030);
const _cViolet = Color(0xFF9B7BE0);
const _cGrey = Color(0xFF8A8F9C);

/// Öffnet das Wochen-Recap einer Liga (optional für einen bestimmten Spieltag).
void showWeeklyRecap(
  BuildContext context, {
  required FantasyLeague league,
  int? round,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WeeklyRecapScreen(league: league, initialRound: round),
    ),
  );
}

/// Stabile Manager-Reihenfolge wie im MatchUp-Tab (Draft-Position, dann ID).
List<String> stableManagerIds(List<FantasyManager> managers) {
  final ids = managers.map((m) => m.userId).toList();
  final posOf = {
    for (final m in managers) m.userId: m.draftPosition ?? 1 << 30,
  };
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
    // Beim Öffnen der zuletzt abgepfiffene Spieltag — der, über den es etwas
    // zu berichten gibt. Zurückblättern geht danach frei.
    final current =
        ref.watch(fantasyRecapRundeProvider).valueOrNull ??
        ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? widget.initialRound ?? current ?? 1;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final stats = statsAsync.valueOrNull ?? const <String, PlayerMatchStats>{};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final bewegungen =
        ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
        const <RosterMove>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Wochen-Recap')),
      body: (managersAsync.isLoading || poolAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final managers = managersAsync.requireValue;
                final pool = poolAsync.requireValue;
                final playerById = {for (final p in pool) p.id: p};
                final nameOf = {for (final m in managers) m.userId: m.display};
                final ids = stableManagerIds(managers);

                final roundFx = [
                  for (final f in allFx)
                    if (f.round == round) f,
                ];
                final live =
                    roundFx.isNotEmpty &&
                    roundFx.any((f) => f.status != FixtureStatus.finished) &&
                    roundFx.any((f) => f.status != FixtureStatus.scheduled);
                final started =
                    roundFx.isNotEmpty &&
                    roundFx.any((f) => f.status != FixtureStatus.scheduled);

                // **Der Kader von damals, nicht der von heute.** Nach dem
                // Abpfiff schneidet der Rückblick ab: Wer später geholt wurde,
                // stand an diesem Spieltag nicht im Kader, und seine Punkte
                // gehören nicht auf diese Bank. („SFV03 hatte keine 230 Punkte
                // auf der Bank.")
                final abpfiff = abpfiffDerRunde(roundFx.map((f) => f.kickoff));
                final kader = abpfiff == null
                    ? roster
                    : kaderAm(
                        aktuell: roster,
                        bewegungen: bewegungen,
                        stichtag: abpfiff,
                      );

                final recap = computeWeeklyRecap(
                  round: round,
                  ids: ids,
                  roster: kader,
                  playerById: playerById,
                  lineups: lineups,
                  stats: stats,
                  scoring: league.scoring,
                  rosterConfig: league.roster,
                );

                void openManager(String id) => showManagerProfile(
                  context,
                  league: league,
                  managerId: id,
                  managerName: nameOf[id] ?? '?',
                );
                void openPlayer(String playerId, bool mine) {
                  final p = playerById[playerId];
                  if (p == null) return;
                  showPlayerProfile(
                    context,
                    league: league,
                    player: p,
                    clubIcon: clubIcons[p.club],
                    isMine: mine,
                  );
                }

                return ListView(
                  children: [
                    MatchdayStepper(
                      round: round,
                      onChanged: (r) => setState(() => _round = r),
                    ),
                    if (statsAsync.isLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    _StatusLine(live: live, started: started),
                    if (ids.length < 2)
                      const _EmptyHint(
                        'Ein Recap braucht mindestens zwei Manager.',
                      )
                    else if (!recap.hasData)
                      _EmptyHint(
                        started
                            ? 'Für diesen Spieltag liegen noch keine gewerteten '
                                  'Punkte vor.'
                            : 'Spieltag $round hat noch nicht begonnen.',
                      )
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
              },
            ),
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
      required double points,
      String? suffix,
    }) {
      cards.add(
        _AwardCard(
          color: color,
          icon: icon,
          title: title,
          primary: name(managerId),
          secondary: suffix,
          value: formatPoints(points),
          valueLabel: 'Pkt',
          highlight: managerId == myId,
          onTap: () => onManager(managerId),
        ),
      );
    }

    void playerAward({
      required Color color,
      required IconData icon,
      required String title,
      required PlayerAward award,
    }) {
      final p = playerById[award.playerId];
      cards.add(
        _AwardCard(
          color: color,
          icon: icon,
          title: title,
          primary: p?.name ?? '?',
          secondary: 'Kader: ${name(award.managerId)}',
          value: formatPoints(award.points),
          valueLabel: 'Pkt',
          highlight: award.managerId == myId,
          badge: p == null
              ? null
              : ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 34),
          onTap: () => onPlayer(award.playerId, award.managerId == myId),
        ),
      );
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
      cards.add(
        _AwardCard(
          color: _cBlue,
          icon: Icons.bolt,
          title: 'Nervenkrimi',
          primary: name(m.winnerId),
          secondary: 'schlägt ${name(m.loserId)} · +${formatPoints(m.margin)}',
          value:
              '${formatPoints(m.winnerPoints)}:${formatPoints(m.loserPoints)}',
          highlight: m.winnerId == myId || m.loserId == myId,
          onTap: () => onManager(m.winnerId),
        ),
      );
    }
    if (recap.blowout != null &&
        recap.blowout!.margin != recap.closestWin?.margin) {
      final m = recap.blowout!;
      cards.add(
        _AwardCard(
          color: _cRed,
          icon: Icons.local_fire_department,
          title: 'Klatsche',
          primary: name(m.winnerId),
          secondary:
              'deklassiert ${name(m.loserId)} · +${formatPoints(m.margin)}',
          value:
              '${formatPoints(m.winnerPoints)}:${formatPoints(m.loserPoints)}',
          highlight: m.winnerId == myId || m.loserId == myId,
          onTap: () => onManager(m.winnerId),
        ),
      );
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
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
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
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
    // **Eine Kante für alle Karten.** Jede Auszeichnung trug ihren Rand in
    // ihrer eigenen Farbe — Gold, Blau, Rot, Grün untereinander, und die
    // hervorgehobene zusätzlich eine gefüllte Fläche derselben Farbe. Ein
    // Regenbogen aus Rändern für eine Liste, in der nichts ansteht.
    //
    // Die Farbe der Auszeichnung sitzt weiterhin da, wo sie hingehört: in der
    // Symbolkachel. Der Hauch bleibt der Karte vorbehalten, in der **du**
    // vorkommst — dasselbe Muster wie bei den Duellen im Tippspiel.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Karte(
        hauch: highlight ? color : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Builder(
          builder: (context) {
            return Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (secondary != null)
                        Text(
                          secondary!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (badge != null) ...[const SizedBox(width: 8), badge!],
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (valueLabel != null)
                      Text(
                        valueLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Kompakte Recap-Kachel: zeigt Team der Woche + MVP eines Spieltags und
/// öffnet auf Tippen das volle Recap.
///
/// **Erst nach dem Abpfiff des letzten Spiels.** Ein Recap ist eine Bilanz —
/// „Team der Woche" mitten im Spieltag benennt den, der zufällig schon
/// gespielt hat, und ändert sich mit jedem Anpfiff wieder. Ohne [runde] nimmt
/// die Kachel den aktuellen Spieltag; die Tabelle reicht dagegen einen
/// **ausgewählten** durch, damit man zurückblättern kann.
class WeeklyRecapCard extends ConsumerWidget {
  const WeeklyRecapCard({super.key, required this.league, this.runde});

  final FantasyLeague league;

  /// Fester Spieltag; `null` = der zuletzt abgepfiffene.
  final int? runde;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Nicht der aktuelle Spieltag, sondern der zurückliegende.** Der
    // aktuelle springt montags um 15:00 weiter; ein Rückblick auf einen
    // Spieltag, der noch gar nicht gespielt ist, wäre leer. Der Rückblick
    // bleibt bis zum Anstoß des nächsten stehen.
    final current = runde ?? ref.watch(fantasyRecapRundeProvider).valueOrNull;
    if (current == null) return const SizedBox.shrink();
    // Kein Recap über einen laufenden Spieltag.
    if (!ref.watch(rundeAbgepfiffenProvider(current))) {
      return const SizedBox.shrink();
    }

    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    if (managers == null || pool == null || managers.length < 2) {
      return const SizedBox.shrink();
    }
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final stats =
        ref.watch(roundStatsProvider(current)).valueOrNull ??
        const <String, PlayerMatchStats>{};

    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.display};
    // Derselbe Schnitt wie im vollen Rückblick: der Kader zum Abpfiff.
    final abpfiff = abpfiffDerRunde([
      for (final f
          in ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
              const <Fixture>[])
        if (f.round == current) f.kickoff,
    ]);
    final kader = abpfiff == null
        ? roster
        : kaderAm(
            aktuell: roster,
            bewegungen:
                ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
                const <RosterMove>[],
            stichtag: abpfiff,
          );
    final recap = computeWeeklyRecap(
      round: current,
      ids: stableManagerIds(managers),
      roster: kader,
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

    // **Dieselbe Hülle wie jede andere Karte.** Vorher lag sie auf einer
    // goldenen Fläche mit goldenem Rand — für einen Rückblick, bei dem nichts
    // zu tun ist. Das Gold trägt jetzt nur noch der Hauch aus der Ecke und
    // die Marke im Inhalt.
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Karte(
        hauch: _cGold,
        radius: 18,
        padding: const EdgeInsets.all(16),
        onTap: () => showWeeklyRecap(context, league: league, round: current),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: _cGold, size: 18),
                const SizedBox(width: 6),
                Text(
                  'RECAP · SPIELTAG ${recap.round}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _cGold,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (top != null)
              _MiniLine(
                label: 'Team der Woche',
                value: nameOf[top.managerId] ?? '?',
                trailing: '${formatPoints(top.points)} Pkt',
              ),
            if (mvp != null) ...[
              const SizedBox(height: 4),
              _MiniLine(
                label: 'MVP',
                value: playerById[mvp.playerId]?.name ?? '?',
                trailing: '${formatPoints(mvp.points)} Pkt',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  const _MiniLine({
    required this.label,
    required this.value,
    required this.trailing,
  });

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
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          trailing,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
