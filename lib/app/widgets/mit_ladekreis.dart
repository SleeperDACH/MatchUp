import 'package:flutter/material.dart';

/// Knopfbeschriftung, vor der während des Speicherns ein Ladekreis steht.
///
/// Seit dem 15.10.2026 (Design-Ideen Punkt 8) tragen Knöpfe mit Wort kein
/// Symbol mehr — das Wort sagt schon, was passiert. Der Symbolplatz hatte aber
/// an einigen Stellen eine zweite Aufgabe: Dort stand während des Speicherns
/// der Ladekreis. Ohne ihn sähe ein laufender Vorgang aus wie ein toter Knopf.
class MitLadekreis extends StatelessWidget {
  const MitLadekreis({super.key, required this.laedt, required this.child});

  final bool laedt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!laedt) return child;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Flexible(child: child),
      ],
    );
  }
}
