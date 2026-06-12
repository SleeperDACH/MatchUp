import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/round_table.dart';
import '../logic/tip_scoring.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'round_selector.dart';

/// Signalfarbe für laufende Spiele (Spielstand & vorläufige Punkte).
const Color _liveColor = Color(0xFFEF6C00); // Orange 800 — in beiden Themes gut

/// Feste Höhen für die zwei nebeneinanderliegenden Tabellenhälften
/// (eingefrorene Namen + scrollende Ergebnisse) — nur so fluchten die
/// Zeilen über die Trennlinie hinweg.
const double _headingHeight = 52;
const double _rowHeight = 48;

/// Tipp-Tabelle à la Kicktipp: alle Mitglieder als Zeilen, die Spiele
/// der gewählten Runde als Spalten. Fremde Tipps erscheinen erst nach
/// Anstoß (serverseitig erzwungen); pro Tipp gibt es die Punkte nach
/// Kicktipp-System, sortiert wird nach Gesamtpunkten. Laufende Spiele
/// sind farblich (orange) markiert und zählen live mit.
class TipsTableTab extends ConsumerWidget {
  const TipsTableTab({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(selectedLeagueProvider);
    final currentRound = ref.watch(currentRoundProvider);

    return currentRound.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (current) {
        final matchday = ref.watch(selectedRoundProvider) ?? current;
        return Column(
          children: [
            RoundSelector(league: league, round: matchday),
            Expanded(child: _TableBody(round: round, matchday: matchday)),
          ],
        );
      },
    );
  }
}

class _TableBody extends ConsumerStatefulWidget {
  const _TableBody({required this.round, required this.matchday});

  final TipRound round;
  final int matchday;

  @override
  ConsumerState<_TableBody> createState() => _TableBodyState();
}

class _TableBodyState extends ConsumerState<_TableBody> {
  /// Auto-Refresh, solange ein Spiel der Runde live ist.
  Timer? _liveTimer;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  /// Startet/stoppt den 60-Sekunden-Takt je nachdem, ob gerade ein
  /// Spiel läuft — kein Polling, wenn alles beendet/geplant ist.
  void _syncAutoRefresh(bool hasLive) {
    if (hasLive && _liveTimer == null) {
      _liveTimer =
          Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
    } else if (!hasLive && _liveTimer != null) {
      _liveTimer!.cancel();
      _liveTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final matchday = widget.matchday;
    final membersAsync = ref.watch(roundMembersProvider(round.id));
    final tipsAsync = ref.watch(allRoundTipsProvider(round.id));
    final fixturesAsync = ref.watch(roundFixturesProvider(matchday));
    final seasonAsync = ref.watch(seasonFixturesProvider);

    if (membersAsync.isLoading ||
        tipsAsync.isLoading ||
        fixturesAsync.isLoading ||
        seasonAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = membersAsync.error ??
        tipsAsync.error ??
        fixturesAsync.error ??
        seasonAsync.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tabelle konnte nicht geladen werden.\n$error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refresh,
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
    }

    final members = [...membersAsync.requireValue];
    final tips = tipsAsync.requireValue;
    final fixtures = fixturesAsync.requireValue;
    final seasonFixtures = seasonAsync.requireValue;
    final rules = round.scoring;
    final myUserId = ref.watch(currentUserProvider)?.id;

    final totals = totalPointsByMember(
      members: members,
      tips: tips,
      fixtures: seasonFixtures,
      rules: rules,
    );
    members.sort((a, b) {
      final byPoints = (totals[b.userId] ?? 0) - (totals[a.userId] ?? 0);
      return byPoints != 0
          ? byPoints
          : a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    final tipByMemberAndFixture = {
      for (final t in tips) '${t.userId}|${t.fixtureId}': t,
    };

    // Auto-Refresh nur, solange ein Spiel der Runde läuft (Seiteneffekt,
    // löst selbst keinen Rebuild aus).
    _syncAutoRefresh(fixtures.any((f) => f.status == FixtureStatus.live));

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            // Zwei fluchtende Tabellen: links der eingefrorene Namens-/Pkt.-
            // Block (scrollt nicht mit), rechts die Ergebnis-Spalten als
            // horizontaler Scroll. Gleiche feste Zeilenhöhen halten beide
            // Hälften zeilengenau auf einer Linie.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: DataTable(
                    columnSpacing: 8,
                    horizontalMargin: 8,
                    headingRowHeight: _headingHeight,
                    dataRowMinHeight: _rowHeight,
                    dataRowMaxHeight: _rowHeight,
                    columns: const [
                      DataColumn(label: Text('Spieler')),
                      DataColumn(label: Text('Pkt.'), numeric: true),
                    ],
                    rows: [
                      for (final member in members)
                        DataRow(
                          cells: [
                            DataCell(SizedBox(
                              width: 84,
                              child: Text(
                                member.username,
                                overflow: TextOverflow.ellipsis,
                                style: member.userId == myUserId
                                    ? const TextStyle(
                                        fontWeight: FontWeight.bold)
                                    : null,
                              ),
                            )),
                            DataCell(Text(
                              '${totals[member.userId] ?? 0}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.primary),
                            )),
                          ],
                        ),
                    ],
                  ),
                ),
                if (fixtures.isNotEmpty)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DataTable(
                        columnSpacing: 14,
                        horizontalMargin: 8,
                        headingRowHeight: _headingHeight,
                        dataRowMinHeight: _rowHeight,
                        dataRowMaxHeight: _rowHeight,
                        columns: [
                          for (final fixture in fixtures)
                            DataColumn(label: _FixtureHeader(fixture: fixture)),
                        ],
                        rows: [
                          for (final member in members)
                            DataRow(
                              cells: [
                                for (final fixture in fixtures)
                                  DataCell(_TipCell(
                                    tip: tipByMemberAndFixture[
                                        '${member.userId}|${fixture.id}'],
                                    fixture: fixture,
                                    isOwn: member.userId == myUserId,
                                    rules: rules,
                                  )),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Text(
              'Punkte: ${rules.exact} Ergebnis · ${rules.goalDiff} Tordifferenz '
              '· ${rules.tendency} Tendenz — fremde Tipps ab Anstoß sichtbar',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          _InviteCodeCard(round: round),
        ],
      ),
    );
  }

  void _refresh() {
    ref.invalidate(roundMembersProvider(widget.round.id));
    ref.invalidate(allRoundTipsProvider(widget.round.id));
    ref.invalidate(roundFixturesProvider(widget.matchday));
    ref.invalidate(seasonFixturesProvider);
  }
}

/// Spaltenkopf: Teamkürzel + Spielstand. Laufende Spiele zeigen den
/// Live-Stand orange mit „LIVE"-Markierung.
class _FixtureHeader extends StatelessWidget {
  const _FixtureHeader({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.labelSmall;
    final live = fixture.status == FixtureStatus.live;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('${fixture.home.shortName} – ${fixture.away.shortName}',
            style: small, textAlign: TextAlign.center),
        if (live && fixture.hasScore) ...[
          Text('${fixture.homeScore}:${fixture.awayScore}',
              style: small?.copyWith(
                  fontWeight: FontWeight.bold, color: _liveColor)),
          const Text('● LIVE',
              style: TextStyle(
                  fontSize: 8, fontWeight: FontWeight.bold, color: _liveColor)),
        ] else
          Text(
            fixture.hasResult
                ? '${fixture.homeScore}:${fixture.awayScore}'
                : (live ? 'LIVE' : '–'),
            style: small?.copyWith(
                fontWeight: FontWeight.bold, color: live ? _liveColor : null),
          ),
      ],
    );
  }
}

class _TipCell extends StatelessWidget {
  const _TipCell({
    required this.tip,
    required this.fixture,
    required this.isOwn,
    required this.rules,
  });

  final MemberTip? tip;
  final Fixture fixture;
  final bool isOwn;
  final ScoringRules rules;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (tip == null) {
      // Vor Anstoß sind fremde Tipps verborgen (Schloss); danach heißt
      // eine leere Zelle „kein Tipp abgegeben".
      return Center(
        child: fixture.hasStarted || isOwn
            ? Text('–', style: TextStyle(color: scheme.onSurfaceVariant))
            : Icon(Icons.lock_outline,
                size: 14, color: scheme.onSurfaceVariant),
      );
    }

    final text = Text('${tip!.homeGoals}:${tip!.awayGoals}');
    if (!fixture.hasScore) return Center(child: text);

    // Live-Spiele werten vorläufig mit; Punkte erscheinen orange, bis
    // das Spiel beendet ist.
    final live = fixture.status == FixtureStatus.live;
    final points = scoreTip(
      tipHome: tip!.homeGoals,
      tipAway: tip!.awayGoals,
      resultHome: fixture.homeScore!,
      resultAway: fixture.awayScore!,
      rules: rules,
    );
    final color = live
        ? _liveColor
        : (points == 0 ? scheme.onSurfaceVariant : scheme.primary);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          text,
          Text('+$points',
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.key),
        title: Text(round.inviteCode,
            style:
                const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5)),
        subtitle: const Text('Einladungscode — antippen zum Kopieren'),
        trailing: const Icon(Icons.copy, size: 18),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: round.inviteCode));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Einladungscode kopiert')));
          }
        },
      ),
    );
  }
}
