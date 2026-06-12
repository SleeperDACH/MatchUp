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

class _TableBody extends ConsumerWidget {
  const _TableBody({required this.round, required this.matchday});

  final TipRound round;
  final int matchday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onPressed: () => _refresh(ref),
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

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DataTable(
                columnSpacing: 14,
                horizontalMargin: 8,
                headingRowHeight: 52,
                columns: [
                  const DataColumn(label: Text('Spieler')),
                  const DataColumn(label: Text('Pkt.'), numeric: true),
                  for (final fixture in fixtures)
                    DataColumn(label: _FixtureHeader(fixture: fixture)),
                ],
                rows: [
                  for (final member in members)
                    DataRow(
                      cells: [
                        DataCell(Text(
                          member.username,
                          style: member.userId == myUserId
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        )),
                        DataCell(Text(
                          '${totals[member.userId] ?? 0}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary),
                        )),
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

  void _refresh(WidgetRef ref) {
    ref.invalidate(roundMembersProvider(round.id));
    ref.invalidate(allRoundTipsProvider(round.id));
    ref.invalidate(roundFixturesProvider(matchday));
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
      children: [
        Text('${fixture.home.shortName} – ${fixture.away.shortName}',
            style: small),
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
      return fixture.hasStarted || isOwn
          ? Text('–', style: TextStyle(color: scheme.onSurfaceVariant))
          : Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant);
    }

    final text = Text('${tip!.homeGoals}:${tip!.awayGoals}');
    if (!fixture.hasScore) return text;

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        text,
        Text('+$points',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      ],
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
