import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/odds/match_odds.dart';
import '../../../core/models/models.dart';
import '../data/tip_store.dart';
import '../logic/tip_scoring.dart';
import '../logic/tip_weeks.dart';
import '../models/tip.dart';
import '../providers.dart';
import 'round_selector.dart';

/// Tippen-Tab: In Runden mit mehreren Wettbewerben ein gemeinsamer
/// Wochen-Feed (alle Ligen zusammen, Woche für Woche); sonst die klassische
/// Spieltag-Ansicht des einzelnen Wettbewerbs.
class MatchdayScreen extends ConsumerWidget {
  const MatchdayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(activeRoundProvider);
    final multi = (round?.competitions.length ?? 0) > 1;
    return multi ? const _WeekTipView() : const _MatchdayTipView();
  }
}

/// Klassische Spieltag-Ansicht eines einzelnen Wettbewerbs (Einzel-Liga-Runden
/// und lokaler Modus).
class _MatchdayTipView extends ConsumerWidget {
  const _MatchdayTipView();

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
            RoundSelector(league: league, round: round),
            Expanded(child: _FixtureList(round: round)),
          ],
        );
      },
    );
  }
}

/// Wochen-Feed für Multi-Wettbewerb-Runden: alle Spiele der gewählten Woche
/// (Do–Mi) über die Wettbewerbe hinweg, nach Anstoß gemischt.
class _WeekTipView extends ConsumerWidget {
  const _WeekTipView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeksAsync = ref.watch(roundWeeksProvider);
    return weeksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: 'Spiele konnten nicht geladen werden.\n$e',
        onRetry: () => ref.invalidate(roundWeeksProvider),
      ),
      data: (weeks) {
        if (weeks.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Keine Spiele gefunden.', textAlign: TextAlign.center),
            ),
          );
        }
        final selected = ref.watch(selectedWeekProvider);
        final index = selected ?? currentWeekIndex(weeks, DateTime.now());
        TipWeek week = weeks.last;
        for (final w in weeks) {
          if (w.index == index) {
            week = w;
            break;
          }
        }
        final odds = ref.watch(weekOddsProvider(week.index));
        final competitions =
            ref.watch(activeRoundProvider)?.competitions ?? const <String>[];
        return Column(
          children: [
            WeekSelector(weeks: weeks, index: week.index),
            Expanded(
              child: _FixtureListBody(
                list: week.fixtures,
                odds: odds,
                onRefresh: () async {
                  ref.invalidate(roundWeeksProvider);
                  for (final id in competitions) {
                    ref.invalidate(leagueSeasonFixturesProvider(id));
                  }
                },
              ),
            ),
          ],
        );
      },
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
      data: (list) => _FixtureListBody(
        list: list,
        odds: ref.watch(roundOddsProvider(round)),
        onRefresh: () async => ref.invalidate(roundFixturesProvider(round)),
      ),
    );
  }
}

/// Rendert eine aufgelöste Spieleliste (Tages-Gruppierung, Tipp-Karten,
/// Sammel-Speichern) — gemeinsam von Spieltag- und Wochen-Pfad genutzt.
class _FixtureListBody extends ConsumerWidget {
  const _FixtureListBody({
    required this.list,
    required this.odds,
    required this.onRefresh,
  });

  final List<Fixture> list;
  final Map<String, MatchOdds> odds;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    // Tipps lassen sich nur abgeben, solange mindestens ein Spiel noch
    // nicht angepfiffen ist.
    final hasOpen = list.any((f) => !f.hasStarted);
    final children = <Widget>[];
    String? lastDay;
    for (final fixture in list) {
      final day = dayFormat.format(fixture.kickoff.toLocal());
      // Datum steht jetzt in der Kopfzeile der Karte (links), die Uhrzeit
      // rechts daneben — außerhalb der Box. Nur beim ersten Spiel eines Tages
      // zeigen wir das Datum, sonst bleibt die Kopfzeile datumslos.
      final isNewDay = day != lastDay;
      if (isNewDay) lastDay = day;
      // Rundenwechsel (lokal ↔ Tipprunde) baut die Karten neu auf,
      // damit die Eingabefelder die Tipps der neuen Quelle zeigen.
      final activeRoundId = ref.watch(activeRoundProvider)?.id ?? 'lokal';
      children.add(FixtureCard(
          key: ValueKey('${fixture.id}:$activeRoundId'),
          fixture: fixture,
          odds: odds[fixture.id],
          dayLabel: isNewDay ? day : null));
    }
    final listView = RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: children,
      ),
    );
    if (!hasOpen) return listView;
    return Column(
      children: [
        _SaveTipsBar(fixtures: list),
        Expanded(child: listView),
      ],
    );
  }
}

class FixtureCard extends ConsumerStatefulWidget {
  const FixtureCard(
      {super.key, required this.fixture, this.odds, this.dayLabel});

  final Fixture fixture;

  /// Bereits auf dieses Spiel gematchte Quoten (oder null) — von der Liste
  /// gereicht, damit die Quelle (Spieltag vs. Woche) hier egal ist.
  final MatchOdds? odds;

  /// Datum für die Kopfzeile über der Box — nur beim ersten Spiel eines Tages
  /// gesetzt, sonst null (dann steht dort nur die Uhrzeit rechts).
  final String? dayLabel;

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

  // Eingabe nur puffern; gespeichert wird gesammelt über „Tipps
  // speichern", damit Fehler dort sichtbar gemeldet werden.
  void _onChanged() {
    ref
        .read(tipDraftProvider.notifier)
        .edit(widget.fixture.id, _homeController.text, _awayController.text);
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    final tip = ref.watch(tipsProvider)[fixture.id];
    final locked = fixture.hasStarted;
    final hasDraft = ref.watch(tipDraftProvider).containsKey(fixture.id);
    final odds = widget.odds;

    // Geladene/aktualisierte Tipps zuverlässig in die Felder spiegeln —
    // auch wenn sie erst nach dem ersten Build ankommen (z. B. beim
    // erneuten Öffnen der App). Nicht überschreiben, solange ein
    // ungespeicherter Entwurf für dieses Spiel existiert.
    ref.listen<Map<String, Tip>>(tipsProvider, (_, next) {
      if (ref.read(tipDraftProvider).containsKey(fixture.id)) return;
      final t = next[fixture.id];
      if (t == null) return;
      final h = t.homeGoals.toString();
      final a = t.awayGoals.toString();
      if (_homeController.text != h) _homeController.text = h;
      if (_awayController.text != a) _awayController.text = a;
    });

    // Vor Anstoß: Tippfelder oben-mittig (wo früher die Uhrzeit stand); nach
    // Anstoß der Spielstand. Quoten (falls vorhanden, nur vor Anstoß) darunter:
    // 1 unter Heim, X in der Mitte, 2 unter Auswärts.
    final Widget center = locked
        ? _CenterInfo(fixture: fixture)
        : _TipInputRow(
            homeController: _homeController,
            awayController: _awayController,
            onChanged: _onChanged,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FixtureHeaderRow(dayLabel: widget.dayLabel, fixture: fixture),
        Card(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _TeamLabel(team: fixture.home)),
                    center,
                    Expanded(
                      child: _TeamLabel(team: fixture.away, alignEnd: true),
                    ),
                  ],
                ),
                if (odds != null && !locked) ...[
                  const SizedBox(height: 6),
                  _UnderOddsRow(odds: odds),
                ],
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _LockedTipRow(fixture: fixture, tip: tip),
                  )
                else
                  _SavedHint(saved: tip != null, dirty: hasDraft),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Kopfzeile über der Spielbox: links das Datum (nur beim ersten Spiel eines
/// Tages), rechts die Uhrzeit — bei laufenden Spielen stattdessen „LIVE".
class _FixtureHeaderRow extends StatelessWidget {
  const _FixtureHeaderRow({required this.dayLabel, required this.fixture});

  final String? dayLabel;
  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = fixture.status == FixtureStatus.live;
    final Widget right = live
        ? Text('LIVE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: scheme.primary))
        : Text(
            DateFormat('HH:mm', 'de_DE').format(fixture.kickoff.toLocal()),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, dayLabel != null ? 14 : 6, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: dayLabel == null
                ? const SizedBox.shrink()
                : Text(
                    dayLabel!,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant),
                  ),
          ),
          right,
        ],
      ),
    );
  }
}

/// Quotenzeile unter den Teams: 1 (unter Heim) · X (Mitte) · 2 (unter Auswärts).
class _UnderOddsRow extends StatelessWidget {
  const _UnderOddsRow({required this.odds});

  final MatchOdds odds;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _OddChip(label: '1', value: odds.homeWin),
          ),
        ),
        _OddChip(label: 'X', value: odds.draw),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _OddChip(label: '2', value: odds.awayWin),
          ),
        ),
      ],
    );
  }
}

/// Einzelne Quote (Label + Wert), dezent — ohne Auswirkung auf die Wertung.
class _OddChip extends StatelessWidget {
  const _OddChip({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
                fontSize: 9,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
          TextSpan(
            text: value.toStringAsFixed(2),
            style: TextStyle(
                fontSize: 12.5,
                height: 1.1,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

/// Sammel-Speichern aller eingegebenen Tipps mit sichtbarer
/// Erfolgs-/Fehlermeldung. Liegt über der Spieleliste.
class _SaveTipsBar extends ConsumerStatefulWidget {
  const _SaveTipsBar({required this.fixtures});

  final List<Fixture> fixtures;

  @override
  ConsumerState<_SaveTipsBar> createState() => _SaveTipsBarState();
}

class _SaveTipsBarState extends ConsumerState<_SaveTipsBar> {
  bool _saving = false;
  bool _savedOk = false;
  List<String> _errors = const [];

  String _label(String fixtureId) {
    for (final f in widget.fixtures) {
      if (f.id == fixtureId) return '${f.home.shortName} – ${f.away.shortName}';
    }
    return fixtureId;
  }

  Future<void> _save() async {
    final draft = ref.read(tipDraftProvider);
    final tips = ref.read(tipsProvider.notifier);
    final draftNotifier = ref.read(tipDraftProvider.notifier);

    setState(() {
      _saving = true;
      _errors = const [];
      _savedOk = false;
    });

    final errors = <String>[];
    var saved = 0;
    for (final entry in draft.entries) {
      final id = entry.key;
      final home = entry.value.home.trim();
      final away = entry.value.away.trim();
      final homeGoals = int.tryParse(home);
      final awayGoals = int.tryParse(away);
      try {
        if (home.isEmpty && away.isEmpty) {
          await tips.clearTip(id);
          draftNotifier.clearEntry(id);
        } else if (homeGoals != null && awayGoals != null) {
          await tips.setTip(id, homeGoals, awayGoals);
          draftNotifier.clearEntry(id);
          saved++;
        } else {
          errors.add('${_label(id)}: Bitte Heim- und Auswärtstore eintragen.');
        }
      } on TipRejected catch (e) {
        errors.add('${_label(id)}: ${e.message}');
      } catch (_) {
        errors.add('${_label(id)}: Speichern fehlgeschlagen — bist du online?');
      }
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _errors = errors;
      _savedOk = errors.isEmpty;
    });

    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(errors.isEmpty
          ? (saved > 0 ? 'Tipps gespeichert.' : 'Keine Änderungen zu speichern.')
          : '${errors.length} Tipp(s) nicht gespeichert.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Beim Weitertippen die Erfolgsmeldung ausblenden. Fehler bleiben
    // dagegen stehen, bis erneut gespeichert wird — ein nicht gespeicherter
    // Tipp soll nicht stillschweigend verschwinden.
    ref.listen(tipDraftProvider, (_, _) {
      if (_savedOk) setState(() => _savedOk = false);
    });

    return Material(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Tipps speichern'),
            ),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in _errors)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          e,
                          style: TextStyle(color: scheme.onErrorContainer),
                        ),
                      ),
                  ],
                ),
              ),
            ] else if (_savedOk) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text('Tipps gespeichert',
                      style: TextStyle(color: scheme.primary)),
                ],
              ),
            ],
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
    // Ohne Vereinslogo — nur der ausgeschriebene Name. Bis zu zwei Zeilen,
    // damit auch längere Namen möglichst vollständig lesbar bleiben.
    return Text(
      team.name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.right : TextAlign.left,
      style: Theme.of(context).textTheme.bodyMedium,
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
    // Boxen mittig unter der Anstoßzeit (= Kartenmitte): das „:" als
    // Mittelpunkt der zentrierten Reihe fluchtet genau darunter.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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

/// Kleiner Status unter der Tipp-Eingabe: „Gespeichert" (grün) sobald
/// ein Tipp serverseitig liegt, „Nicht gespeichert" (orange) bei
/// ungespeicherter Änderung. Aktualisiert sich beim Tippen und nach dem
/// Druck auf „Tipps speichern".
class _SavedHint extends StatelessWidget {
  const _SavedHint({required this.saved, required this.dirty});

  final bool saved;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String label) = dirty
        ? (Icons.edit_outlined, const Color(0xFFF23030), 'Nicht gespeichert')
        : saved
            ? (Icons.check_circle, const Color(0xFF4ADE6A), 'Gespeichert')
            : (Icons.remove, Colors.transparent, '');
    if (label.isEmpty) return const SizedBox(height: 6);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
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
