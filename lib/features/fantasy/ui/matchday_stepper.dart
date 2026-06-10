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
          icon: const Icon(Icons.chevron_right),
          onPressed: round < max ? () => onChanged(round + 1) : null,
        ),
      ],
    );
  }
}
