import 'package:flutter/material.dart';

/// Spieltag-Auswahl (1..[max]) für die Fantasy-Wertung.
class MatchdayStepper extends StatelessWidget {
  const MatchdayStepper({
    super.key,
    required this.round,
    required this.onChanged,
    this.max = 34,
  });

  final int round;
  final ValueChanged<int> onChanged;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          // Das Ziel im Namen, nicht die Richtung allein: „Schaltfläche,
          // Schaltfläche" links und rechts von „Spieltag 7" sagte nicht,
          // welcher Spieltag hinter welchem Pfeil liegt.
          tooltip: round > 1 ? 'Zurück zu Spieltag ${round - 1}' : 'Zurück',
          icon: const Icon(Icons.chevron_left),
          onPressed: round > 1 ? () => onChanged(round - 1) : null,
        ),
        SizedBox(
          width: 130,
          child: Text('Spieltag $round',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: round < max ? 'Weiter zu Spieltag ${round + 1}' : 'Weiter',
          icon: const Icon(Icons.chevron_right),
          onPressed: round < max ? () => onChanged(round + 1) : null,
        ),
      ],
    );
  }
}
