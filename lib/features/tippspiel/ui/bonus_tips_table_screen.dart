import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'team_badge.dart';

/// Zweite Tabelle auf dem Tabellen-Tab: die Bonustipps aller Mitglieder als
/// Matrix (Mitglied × Frage). Fremde Antworten erscheinen erst nach der
/// Deadline (erster Spieltag) — vorher nur die eigene Zeile.
class BonusTipsTableScreen extends ConsumerWidget {
  const BonusTipsTableScreen({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = round.scoring.bonusTips;
    final membersAsync = ref.watch(roundMembersProvider(round.id));
    final answersAsync = ref.watch(bonusAnswersProvider(round.id));
    final fixtures =
        ref.watch(leagueSeasonFixturesProvider(round.leagueId)).valueOrNull ??
            const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;

    final teamsById = <String, TeamRef>{};
    for (final f in fixtures) {
      teamsById[f.home.id] = f.home;
      teamsById[f.away.id] = f.away;
    }
    DateTime? deadline;
    for (final f in fixtures) {
      if (deadline == null || f.kickoff.isBefore(deadline)) {
        deadline = f.kickoff;
      }
    }
    final revealed = deadline != null && !DateTime.now().isBefore(deadline);

    return Scaffold(
      appBar: AppBar(title: const Text('Bonustipp-Tabelle')),
      body: (membersAsync.isLoading || answersAsync.isLoading)
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final members = membersAsync.valueOrNull ?? const [];
              final answers = answersAsync.valueOrNull ?? const [];
              // userId → question → Teams.
              final byUserQ = <String, Map<String, List<TeamRef>>>{};
              for (final a in answers) {
                final team = teamsById[a.teamId] ??
                    TeamRef(id: a.teamId, name: a.teamName, shortName: a.teamName);
                byUserQ
                    .putIfAbsent(a.userId, () => {})
                    .putIfAbsent(a.question, () => [])
                    .add(team);
              }

              return Column(
                children: [
                  if (!revealed)
                    Container(
                      width: double.infinity,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.10),
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        'Die Tipps der anderen werden erst zum ersten Spieltag '
                        'sichtbar. Punkte: ${round.scoring.bonusPoints} je '
                        'richtiger Frage.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 18,
                          columns: [
                            const DataColumn(label: Text('Mitglied')),
                            for (final q in questions)
                              DataColumn(label: Text(bonusTipLabel(q))),
                          ],
                          rows: [
                            for (final m in members)
                              DataRow(cells: [
                                DataCell(Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppAvatar(
                                      imageUrl: m.avatarUrl,
                                      emoji: m.avatarEmoji,
                                      colorHex: m.avatarColor,
                                      fallbackText: m.display,
                                      size: 24,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      m.display,
                                      style: m.userId == myId
                                          ? const TextStyle(
                                              fontWeight: FontWeight.bold)
                                          : null,
                                    ),
                                  ],
                                )),
                                for (final q in questions)
                                  DataCell(_cell(
                                    teams: byUserQ[m.userId]?[q] ?? const [],
                                    hidden: !revealed && m.userId != myId,
                                  )),
                              ]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
    );
  }

  Widget _cell({required List<TeamRef> teams, required bool hidden}) {
    if (hidden) {
      return const Icon(Icons.lock_outline, size: 16, color: Colors.grey);
    }
    if (teams.isEmpty) return const Text('—');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in teams)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TeamBadge(team: t, size: 18),
                const SizedBox(width: 5),
                Text(t.shortName),
              ],
            ),
          ),
      ],
    );
  }
}
