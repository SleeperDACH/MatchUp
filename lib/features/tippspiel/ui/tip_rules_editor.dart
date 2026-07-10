import 'package:flutter/material.dart';

import '../models/tip.dart';

/// Wiederverwendbares Formular für Basiswertung + kombinierbare Modi einer
/// Tipprunde. Genutzt beim Erstellen und in den Liga-Einstellungen. Meldet
/// jede Änderung als komplette [ScoringRules] über [onChanged]; Name und
/// Wettbewerb liegen bewusst außerhalb (die sind nicht Teil der Wertung).
class TipRulesEditor extends StatefulWidget {
  const TipRulesEditor({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  final ScoringRules initial;
  final ValueChanged<ScoringRules> onChanged;

  @override
  State<TipRulesEditor> createState() => _TipRulesEditorState();
}

class _TipRulesEditorState extends State<TipRulesEditor> {
  late int _exact = widget.initial.exact;
  late int _goalDiff = widget.initial.goalDiff;
  late int _tendency = widget.initial.tendency;

  late bool _oddsBonus = widget.initial.oddsBonus;
  late double _odds1 = widget.initial.oddsOdds1;
  late int _points1 = widget.initial.oddsPoints1;
  late double _odds2 = widget.initial.oddsOdds2;
  late int _points2 = widget.initial.oddsPoints2;

  late bool _solo = widget.initial.solo > 0;
  // Punkte des Alleinstellungs-Bonus (Bestand erhalten, sonst Standard 3).
  late final int _soloValue = widget.initial.solo > 0 ? widget.initial.solo : 3;

  late bool _headToHead = widget.initial.headToHead;

  late bool _bonusTips = widget.initial.bonusTips.isNotEmpty;
  late final Set<String> _bonusTipKeys = widget.initial.bonusTips.isNotEmpty
      ? {...widget.initial.bonusTips}
      : {for (final o in bonusTipQuestions) o.$1};
  late int _bonusPoints = widget.initial.bonusPoints;

  ScoringRules get _rules => ScoringRules(
        exact: _exact,
        goalDiff: _goalDiff,
        tendency: _tendency,
        oddsBonus: _oddsBonus,
        oddsOdds1: _odds1,
        oddsPoints1: _points1,
        oddsOdds2: _odds2,
        oddsPoints2: _points2,
        solo: _solo ? _soloValue : 0,
        headToHead: _headToHead,
        bonusTips: _bonusTips
            ? [
                for (final o in bonusTipQuestions)
                  if (_bonusTipKeys.contains(o.$1)) o.$1
              ]
            : const [],
        bonusPoints: _bonusPoints,
      );

  /// setState + Änderung nach oben melden.
  void _set(VoidCallback change) {
    setState(change);
    widget.onChanged(_rules);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Basiswertung', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
            'Punkte je Tipp — exaktes Ergebnis, richtige Tordifferenz, '
            'nur richtige Tendenz.',
            style: subtle),
        const SizedBox(height: 12),
        _PointsStepper(
            label: 'Exaktes Ergebnis',
            value: _exact,
            onChanged: (v) => _set(() => _exact = v)),
        _PointsStepper(
            label: 'Tordifferenz',
            value: _goalDiff,
            onChanged: (v) => _set(() => _goalDiff = v)),
        _PointsStepper(
            label: 'Tendenz',
            value: _tendency,
            onChanged: (v) => _set(() => _tendency = v)),
        const SizedBox(height: 24),
        Text('Modi', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Frei kombinierbar — beliebig viele gleichzeitig aktivieren.',
            style: subtle),
        const SizedBox(height: 8),
        _ModeSwitch(
          icon: Icons.trending_up,
          title: 'Quoten-Bonus',
          subtitle:
              'Extrapunkte für richtig getippte Außenseiter — je höher die Quote, desto mehr.',
          value: _oddsBonus,
          onChanged: (v) => _set(() => _oddsBonus = v),
        ),
        if (_oddsBonus) _oddsConfig(scheme),
        _ModeSwitch(
          icon: Icons.workspace_premium_outlined,
          title: 'Alleinstellungs-Bonus',
          subtitle:
              'Wer als Einzige/r das exakte Ergebnis trifft, bekommt +$_soloValue Punkte.',
          value: _solo,
          onChanged: (v) => _set(() => _solo = v),
        ),
        _ModeSwitch(
          icon: Icons.bolt_outlined,
          title: 'Head-to-Head',
          subtitle:
              'Jeder Spieltag als Duell zwischen zwei Mitgliedern (Sieg/Niederlage).',
          value: _headToHead,
          onChanged: (v) => _set(() => _headToHead = v),
        ),
        _ModeSwitch(
          icon: Icons.emoji_events_outlined,
          title: 'Bonustipps',
          subtitle:
              'Saison-Prognosen zusätzlich zu den Spieltagen — auswählbar unten.',
          value: _bonusTips,
          onChanged: (v) => _set(() => _bonusTips = v),
        ),
        if (_bonusTips) _bonusTipsConfig(scheme),
      ],
    );
  }

  /// Konfiguration des Quoten-Bonus: zwei Stufen (Quote + Punkte).
  Widget _oddsConfig(ColorScheme scheme) {
    Widget tier({
      required String title,
      required double odds,
      required int points,
      required ValueChanged<double> onOdds,
      required ValueChanged<int> onPoints,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            _OddsStepper(label: 'Ab Quote', value: odds, onChanged: onOdds),
            _PointsStepper(label: 'Punkte', value: points, onChanged: onPoints),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          tier(
            title: 'Außenseiter',
            odds: _odds1,
            points: _points1,
            onOdds: (v) => _set(() => _odds1 = v),
            onPoints: (v) => _set(() => _points1 = v),
          ),
          const Divider(height: 12),
          tier(
            title: 'Krasser Außenseiter',
            odds: _odds2,
            points: _points2,
            onOdds: (v) => _set(() => _odds2 = v),
            onPoints: (v) => _set(() => _points2 = v),
          ),
        ],
      ),
    );
  }

  /// Auswahl der enthaltenen Bonustipps + Punkte.
  Widget _bonusTipsConfig(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (final (key, label, maxTeams) in bonusTipQuestions)
              CheckboxListTile(
                dense: true,
                value: _bonusTipKeys.contains(key),
                onChanged: (v) => _set(() {
                  if (v == true) {
                    _bonusTipKeys.add(key);
                  } else {
                    _bonusTipKeys.remove(key);
                  }
                }),
                title: Text(label),
                subtitle: maxTeams > 1 ? Text('$maxTeams Teams') : null,
              ),
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PointsStepper(
                label: 'Punkte je richtiger Bonustipp',
                value: _bonusPoints,
                onChanged: (v) => _set(() => _bonusPoints = v),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kleiner +/- Stepper für einen Punktewert (0–20).
class _PointsStepper extends StatelessWidget {
  const _PointsStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('$value',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 20 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// +/- Stepper für eine Quote (1,5–10,0 in 0,5-Schritten).
class _OddsStepper extends StatelessWidget {
  const _OddsStepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > 1.5 ? () => onChanged(value - 0.5) : null,
          ),
          SizedBox(
            width: 34,
            child: Text(value.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < 10.0 ? () => onChanged(value + 0.5) : null,
          ),
        ],
      ),
    );
  }
}

/// Ein Modus-Umschalter (unabhängig kombinierbar).
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: value ? scheme.primary.withValues(alpha: 0.12) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: value ? scheme.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon,
            color: value ? scheme.primary : scheme.onSurfaceVariant),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
      ),
    );
  }
}
