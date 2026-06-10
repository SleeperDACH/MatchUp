import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../data/tip_store.dart';
import '../logic/tip_scoring.dart';
import '../models/tip.dart';
import '../providers.dart';
import 'team_badge.dart';

/// Spieltag-Ansicht: alle Spiele einer Runde mit Tipp-Eingabe.
class MatchdayScreen extends ConsumerWidget {
  const MatchdayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = ref.watch(selectedLeagueProvider);
    final currentRound = ref.watch(currentRoundProvider);

    return currentRound.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Spieltag konnte nicht geladen werden.\n$e',
        onRetry: () => ref.invalidate(currentRoundProvider),
      ),
      data: (current) {
        final round = ref.watch(selectedRoundProvider) ?? current;
        return Column(
          children: [
            _RoundSelector(league: league, round: round),
            Expanded(child: _FixtureList(round: round)),
          ],
        );
      },
    );
  }
}

class _RoundSelector extends ConsumerWidget {
  const _RoundSelector({required this.league, required this.round});

  final LeagueInfo league;
  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Offizielle Rundenliste („Gruppenphase 1" … „Finale"): begrenzt die
    // Navigation und zeigt bei Turnieren auch K.o.-Runden, deren
    // Paarungen noch nicht feststehen.
    final rounds = ref.watch(availableRoundsProvider).valueOrNull;

    String label = '${league.roundLabel} $round';
    int? previous = round > 1 ? round - 1 : null;
    int? next = round + 1;
    if (rounds != null && rounds.isNotEmpty) {
      final index = rounds.indexWhere((r) => r.number == round);
      if (index >= 0) {
        if (rounds[index].name.isNotEmpty) label = rounds[index].name;
        previous = index > 0 ? rounds[index - 1].number : null;
        next = index < rounds.length - 1 ? rounds[index + 1].number : null;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: previous == null
                ? null
                : () =>
                    ref.read(selectedRoundProvider.notifier).state = previous,
          ),
          SizedBox(
            width: 180,
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: next == null
                ? null
                : () => ref.read(selectedRoundProvider.notifier).state = next,
          ),
        ],
      ),
    );
  }
}

class _FixtureList extends ConsumerWidget {
  const _FixtureList({required this.round});

  final int round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = ref.watch(roundFixturesProvider(round));
    return fixtures.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Spiele konnten nicht geladen werden.\n$e',
        onRetry: () => ref.invalidate(roundFixturesProvider(round)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Die Paarungen dieser Runde stehen noch nicht fest.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final dayFormat = DateFormat('EEEE, d. MMMM', 'de_DE');
        final children = <Widget>[];
        String? lastDay;
        for (final fixture in list) {
          final day = dayFormat.format(fixture.kickoff.toLocal());
          if (day != lastDay) {
            lastDay = day;
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                day,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ));
          }
          // Rundenwechsel (lokal ↔ Tipprunde) baut die Karten neu auf,
          // damit die Eingabefelder die Tipps der neuen Quelle zeigen.
          final activeRoundId = ref.watch(activeRoundProvider)?.id ?? 'lokal';
          children.add(FixtureCard(
              key: ValueKey('${fixture.id}:$activeRoundId'),
              fixture: fixture));
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(roundFixturesProvider(round)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: children,
          ),
        );
      },
    );
  }
}

class FixtureCard extends ConsumerStatefulWidget {
  const FixtureCard({super.key, required this.fixture});

  final Fixture fixture;

  @override
  ConsumerState<FixtureCard> createState() => _FixtureCardState();
}

class _FixtureCardState extends ConsumerState<FixtureCard> {
  late final TextEditingController _homeController;
  late final TextEditingController _awayController;

  @override
  void initState() {
    super.initState();
    final tip = ref.read(tipsProvider)[widget.fixture.id];
    _homeController =
        TextEditingController(text: tip?.homeGoals.toString() ?? '');
    _awayController =
        TextEditingController(text: tip?.awayGoals.toString() ?? '');
  }

  @override
  void dispose() {
    _homeController.dispose();
    _awayController.dispose();
    super.dispose();
  }

  Future<void> _onChanged() async {
    final home = int.tryParse(_homeController.text);
    final away = int.tryParse(_awayController.text);
    final notifier = ref.read(tipsProvider.notifier);
    try {
      if (home != null && away != null) {
        await notifier.setTip(widget.fixture.id, home, away);
      } else if (_homeController.text.isEmpty &&
          _awayController.text.isEmpty) {
        await notifier.clearTip(widget.fixture.id);
      }
    } on TipRejected catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Tipp konnte nicht gespeichert werden — bist du online?');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final tip = ref.watch(tipsProvider)[fixture.id];
    final locked = fixture.hasStarted;

    // Falls der Tipp anderswo geladen wurde (z. B. asynchron aus dem
    // lokalen Speicher), Eingabefelder nachziehen — aber nie während
    // der Nutzer tippt.
    if (tip != null &&
        _homeController.text.isEmpty &&
        _awayController.text.isEmpty &&
        !FocusScope.of(context).hasFocus) {
      _homeController.text = tip.homeGoals.toString();
      _awayController.text = tip.awayGoals.toString();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _TeamLabel(team: fixture.home)),
                _CenterInfo(fixture: fixture),
                Expanded(
                  child: _TeamLabel(team: fixture.away, alignEnd: true),
                ),
              ],
            ),
            const SizedBox(height: 10),
            locked
                ? _LockedTipRow(fixture: fixture, tip: tip)
                : _TipInputRow(
                    homeController: _homeController,
                    awayController: _awayController,
                    onChanged: _onChanged,
                  ),
          ],
        ),
      ),
    );
  }
}

class _TeamLabel extends StatelessWidget {
  const _TeamLabel({required this.team, this.alignEnd = false});

  final TeamRef team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final avatar = TeamBadge(team: team);
    final name = Flexible(
      child: Text(
        team.shortName,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [name, const SizedBox(width: 8), avatar]
          : [avatar, const SizedBox(width: 8), name],
    );
  }
}

class _CenterInfo extends StatelessWidget {
  const _CenterInfo({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.titleMedium;
    switch (fixture.status) {
      case FixtureStatus.finished:
        return Text('${fixture.homeScore} : ${fixture.awayScore}',
            style: style);
      case FixtureStatus.live:
        final score = fixture.homeScore != null
            ? '${fixture.homeScore} : ${fixture.awayScore}'
            : '0 : 0';
        return Column(
          children: [
            Text(score, style: style?.copyWith(color: scheme.primary)),
            Text('LIVE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary)),
          ],
        );
      case FixtureStatus.scheduled:
        return Text(
          DateFormat('HH:mm', 'de_DE').format(fixture.kickoff.toLocal()),
          style: style?.copyWith(color: scheme.onSurfaceVariant),
        );
    }
  }
}

class _TipInputRow extends StatelessWidget {
  const _TipInputRow({
    required this.homeController,
    required this.awayController,
    required this.onChanged,
  });

  final TextEditingController homeController;
  final TextEditingController awayController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Tipp:',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(width: 12),
        _GoalField(controller: homeController, onChanged: onChanged),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(':'),
        ),
        _GoalField(controller: awayController, onChanged: onChanged),
      ],
    );
  }
}

class _GoalField extends StatelessWidget {
  const _GoalField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 38,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        // Hält das Eingabefeld beim Fokussieren oberhalb der Tastatur.
        scrollPadding: const EdgeInsets.only(bottom: 120),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _LockedTipRow extends ConsumerWidget {
  const _LockedTipRow({required this.fixture, required this.tip});

  final Fixture fixture;
  final Tip? tip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: scheme.onSurfaceVariant);

    if (tip == null) {
      return Text('Kein Tipp abgegeben', style: labelStyle);
    }

    final children = <Widget>[
      Icon(Icons.lock_outline, size: 14, color: scheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Text('Tipp: ${tip!.homeGoals} : ${tip!.awayGoals}', style: labelStyle),
    ];

    if (fixture.hasResult) {
      final points = scoreTip(
        tipHome: tip!.homeGoals,
        tipAway: tip!.awayGoals,
        resultHome: fixture.homeScore!,
        resultAway: fixture.awayScore!,
        rules: ref.watch(scoringRulesProvider),
      );
      children.addAll([
        const SizedBox(width: 10),
        _PointsChip(points: points),
      ]);
    }

    return Row(mainAxisAlignment: MainAxisAlignment.center, children: children);
  }
}

class _PointsChip extends StatelessWidget {
  const _PointsChip({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = points > 0 ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '+$points',
        style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
          ],
        ),
      ),
    );
  }
}
