import 'package:flutter/material.dart';

/// **Ein +/−-Stepper mit benannten Knöpfen.**
///
/// Lag privat in der Einstellungsseite und wird seit der Auslagerung des
/// Kader-Limit-Editors an zwei Stellen gebraucht. Das Wichtige daran ist die
/// Beschriftung: Ohne sie hießen für die Vorlesehilfe beide Knöpfe
/// „Schaltfläche", auf jeder Zeile dieselben zwei.

class WertStepper extends StatelessWidget {
  const WertStepper(
      {super.key,
      required this.label,
      required this.value,
      required this.min,
      required this.max,
      required this.onChanged});

  /// Die Beschriftung der Zeile, in der der Stepper sitzt. Er steht
  /// dort rechts neben ihr und wusste selbst nicht, was er zählt — für die
  /// Vorlesehilfe hießen beide Knöpfe „Schaltfläche", auf jeder der fünf
  /// Zeilen dieselben zwei.
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: '$label verringern',
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        // Die Zahl bleibt als eigene Station stehen: Die umgebende
        // Zeile sagt nur ihre Beschriftung an, den Wert trägt allein
        // dieser Text. Ein zweites „Anzahl Runden" davorzusetzen hätte die
        // Beschriftung in einer Zeile viermal wiederholt — zwischen zwei
        // benannten Knöpfen steht die Zahl auch so am richtigen Platz.
        SizedBox(
          width: 28,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        IconButton(
          tooltip: '$label erhöhen',
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
