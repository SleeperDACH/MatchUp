import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../logic/fantasy_scoring_engine.dart' show formatPoints;
import '../models/fantasy_models.dart';
import 'wert_stepper.dart';

/// **Unentschieden bei knappem Ausgang** — Schalter plus Abstand (1–20).
///
/// Derselbe Baustein beim Erstellen der Liga und in den Einstellungen; zwei
/// Fassungen davon liefen beim nächsten Feinschliff auseinander (dieselbe
/// Begründung wie beim `KaderLimitsEditor`). Er kennt keine Liga, nur den
/// Wert: `null` = aus, sonst der höchste Abstand in Punkten.
class RemisGrenzeEditor extends StatelessWidget {
  const RemisGrenzeEditor({
    super.key,
    required this.wert,
    required this.onChanged,
    this.aenderbar = true,
  });

  final double? wert;
  final ValueChanged<double?> onChanged;

  /// Nur der Ersteller darf ändern; alle anderen sehen die Regel.
  final bool aenderbar;

  static const min = 1;
  static const max = 20;

  /// Kurzfassung für Untertitel und Erklärungen.
  static String text(double? wert) => wert == null
      ? 'Nur bei Punktgleichheit'
      : 'Bis ${formatPoints(wert)} Punkte Abstand';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final an = wert != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Unentschieden bei knappem Ausgang'),
          subtitle: Text(an
              ? 'Liegen beide höchstens ${formatPoints(wert!)} Punkte '
                  'auseinander, endet das Duell unentschieden.'
              : 'Aus — unentschieden nur bei exakt gleicher Punktzahl.'),
          value: an,
          onChanged: aenderbar
              ? (v) => onChanged(v ? FantasyLeague.remisGrenzeStandard : null)
              : null,
        ),
        if (an)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Abstand in Punkten',
                    style: TextStyle(
                      fontSize: Schrift.text,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (aenderbar)
                  WertStepper(
                    label: 'Abstand für Unentschieden',
                    value: wert!.round().clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: (v) => onChanged(v.toDouble()),
                  )
                else
                  Text(formatPoints(wert!),
                      style: const TextStyle(
                          fontSize: Schrift.titel,
                          fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}
