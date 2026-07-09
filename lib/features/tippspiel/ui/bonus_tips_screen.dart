import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'team_badge.dart';

/// Abgabe der Bonustipps (Saison-Prognosen) — je aktivierter Frage ein Team
/// (Absteiger: zwei). Abgabe/Änderung nur **vor dem ersten Spieltag**; danach
/// nur noch lesbar. Gespeichert wird erst mit dem „Speichern"-Knopf.
class BonusTipsScreen extends ConsumerStatefulWidget {
  const BonusTipsScreen({super.key, required this.round});

  final TipRound round;

  @override
  ConsumerState<BonusTipsScreen> createState() => _BonusTipsScreenState();
}

class _BonusTipsScreenState extends ConsumerState<BonusTipsScreen> {
  // Aktuelle Auswahl je Frage (bis zu max. Teams). Lokal, bis „Speichern".
  final Map<String, List<TeamRef>> _picks = {};
  bool _loaded = false;
  bool _saving = false;
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final questions = round.scoring.bonusTips;
    final fixturesAsync =
        ref.watch(leagueSeasonFixturesProvider(round.leagueId));
    final answersAsync = ref.watch(bonusAnswersProvider(round.id));
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Bonustipps')),
      body: fixturesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (fixtures) {
          final teamsById = <String, TeamRef>{};
          for (final f in fixtures) {
            teamsById[f.home.id] = f.home;
            teamsById[f.away.id] = f.away;
          }
          final teams = teamsById.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name));

          DateTime? deadline;
          for (final f in fixtures) {
            if (deadline == null || f.kickoff.isBefore(deadline)) {
              deadline = f.kickoff;
            }
          }
          final open = deadline == null || DateTime.now().isBefore(deadline);

          // Einmalige Initialisierung der Auswahl aus den gespeicherten Antworten.
          if (!_loaded && answersAsync.hasValue) {
            final mine = [
              for (final a in answersAsync.value!)
                if (a.userId == myId) a
            ];
            for (final q in questions) {
              _picks[q] = [
                for (final a in mine)
                  if (a.question == q)
                    teamsById[a.teamId] ??
                        TeamRef(id: a.teamId, name: a.teamName, shortName: a.teamName)
              ];
            }
            _loaded = true;
          }

          if (teams.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Noch keine Teams für diesen Wettbewerb geladen.',
                    textAlign: TextAlign.center),
              ),
            );
          }

          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _DeadlineBanner(open: open, deadline: deadline),
                  const SizedBox(height: 8),
                  for (final q in questions)
                    _QuestionCard(
                      title: bonusTipLabel(q),
                      maxTeams: bonusTipMax(q),
                      teams: teams,
                      picks: _picks[q] ?? const [],
                      enabled: open && !_saving,
                      onChanged: (list) => setState(() {
                        _picks[q] = list;
                        _saved = false;
                      }),
                    ),
                ],
              ),
              if (open)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: FilledButton.icon(
                    style: _saved
                        ? FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.primary)
                        : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_saved
                            ? Icons.check_circle
                            : Icons.save_outlined),
                    label: Text(_saved ? 'Gespeichert ✓' : 'Speichern'),
                    onPressed: _saving ? null : _save,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    try {
      final repo = ref.read(tipRoundRepositoryProvider);
      for (final q in widget.round.scoring.bonusTips) {
        await repo.setBonusAnswers(
          roundId: widget.round.id,
          question: q,
          teams: [for (final t in _picks[q] ?? const []) (id: t.id, name: t.name)],
        );
      }
      ref.invalidate(bonusAnswersProvider(widget.round.id));
      if (!mounted) return;
      setState(() => _saved = true);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.primary,
        content: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Bonustipps gespeichert.'),
          ],
        ),
      ));
      // Bestätigung am Knopf nach kurzer Zeit zurücksetzen.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _saved = false);
      });
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DeadlineBanner extends StatelessWidget {
  const _DeadlineBanner({required this.open, required this.deadline});

  final bool open;
  final DateTime? deadline;

  static const _months = [
    'Jan', 'Feb', 'März', 'Apr', 'Mai', 'Juni',
    'Juli', 'Aug', 'Sept', 'Okt', 'Nov', 'Dez'
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = open ? scheme.primary : scheme.error;
    String text;
    if (!open) {
      text = 'Abgabe geschlossen — der erste Spieltag hat begonnen.';
    } else if (deadline != null) {
      final d = deadline!.toLocal();
      text = 'Abgabe bis zum ersten Anstoß: '
          '${d.day}. ${_months[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')} Uhr.';
    } else {
      text = 'Wähle je Frage dein Team. Änderbar bis zum ersten Spieltag.';
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(open ? Icons.timelapse : Icons.lock_outline,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.title,
    required this.maxTeams,
    required this.teams,
    required this.picks,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final int maxTeams;
  final List<TeamRef> teams;
  final List<TeamRef> picks;
  final bool enabled;
  final ValueChanged<List<TeamRef>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (var slot = 0; slot < maxTeams; slot++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _slotDropdown(context, slot),
              ),
          ],
        ),
      ),
    );
  }

  Widget _slotDropdown(BuildContext context, int slot) {
    final current = slot < picks.length ? picks[slot] : null;
    // In anderen Slots derselben Frage gewählte Teams ausschließen.
    final takenElsewhere = {
      for (var i = 0; i < picks.length; i++)
        if (i != slot) picks[i].id
    };
    return DropdownButtonFormField<String>(
      initialValue: current != null && teams.any((t) => t.id == current.id)
          ? current.id
          : null,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: maxTeams > 1 ? 'Team ${slot + 1} wählen' : 'Team wählen',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      items: [
        for (final t in teams)
          if (!takenElsewhere.contains(t.id))
            DropdownMenuItem(
              value: t.id,
              child: Row(
                children: [
                  TeamBadge(team: t, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
      ],
      onChanged: enabled
          ? (id) {
              final next = [...picks];
              if (id == null) {
                if (slot < next.length) next.removeAt(slot);
              } else {
                final team = teams.firstWhere((t) => t.id == id);
                if (slot < next.length) {
                  next[slot] = team;
                } else {
                  next.add(team); // erster Eintrag dieses Slots
                }
              }
              onChanged(next);
            }
          : null,
    );
  }
}
