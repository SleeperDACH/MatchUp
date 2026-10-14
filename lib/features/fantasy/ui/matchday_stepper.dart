import 'package:flutter/material.dart';

/// Spieltag-Auswahl (1..[max]) für die Fantasy-Wertung.
class MatchdayStepper extends StatelessWidget {
  const MatchdayStepper({
    super.key,
    required this.round,
    required this.onChanged,
    this.max = 34,
    this.kompakt = false,
  });

  final int round;
  final ValueChanged<int> onChanged;
  final int max;

  /// Schmale Fassung für eine Kopfzeile — „‹ Spieltag 7 ›" rechts neben einer
  /// Überschrift, wie bei Sleeper über der Startelf. Die Beschriftung trägt
  /// dann die Markenfarbe: Sie ist dort das einzige, was man antippen kann.
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: kompakt ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          // Das Ziel im Namen, nicht die Richtung allein: „Schaltfläche,
          // Schaltfläche" links und rechts von „Spieltag 7" sagte nicht,
          // welcher Spieltag hinter welchem Pfeil liegt.
          tooltip: round > 1 ? 'Zurück zu Spieltag ${round - 1}' : 'Zurück',
          icon: Icon(Icons.chevron_left,
              color: kompakt && round > 1 ? scheme.primary : null),
          visualDensity: kompakt ? VisualDensity.compact : null,
          onPressed: round > 1 ? () => onChanged(round - 1) : null,
        ),
        SizedBox(
          width: kompakt ? 92 : 130,
          child: Text('Spieltag $round',
              textAlign: TextAlign.center,
              style: kompakt
                  ? Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w800)
                  : Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: round < max ? 'Weiter zu Spieltag ${round + 1}' : 'Weiter',
          icon: Icon(Icons.chevron_right,
              color: kompakt && round < max ? scheme.primary : null),
          visualDensity: kompakt ? VisualDensity.compact : null,
          onPressed: round < max ? () => onChanged(round + 1) : null,
        ),
      ],
    );
  }
}
