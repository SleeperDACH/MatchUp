import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../logic/fantasy_scoring_engine.dart' show formatPoints;
import '../models/fantasy_models.dart';
import '../../../core/ui/wert_stepper.dart';

/// **Unentschieden bei knappem Ausgang** — Schalter plus Abstand (5–50 in Fünferschritten).
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

  /// 5 bis 50 in Fünferschritten (19.10.2026, auf Ansage; vorher 1–20).
  /// Dieselbe Regel steht als Check in Migration 0138.
  static const min = 5;
  static const max = 50;
  static const schritt = 5;

  /// Auf den nächsten erlaubten Wert — ein alter Wert wie 3 wird 5.
  static int erlaubt(double wert) =>
      ((wert / schritt).round() * schritt).clamp(min, max);

  /// Kurzfassung für Untertitel und Erklärungen.
  static String text(double? wert) => wert == null
      ? 'Nur bei Punktgleichheit'
      : 'Bis ${formatPoints(wert)} Punkte Abstand';

  @override
  Widget build(BuildContext context) {
    final an = wert != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // **Eine Zeile wie jede andere** (18.10.2026): Bezeichnung in
        // Textgröße, darunter der Stand in einer kurzen Zeile. Der Satz
        // „Liegen beide höchstens … auseinander" stand vorher darunter und
        // sagte, was die Zahl ohnehin sagt.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bei knappem Ausgang',
              style: TextStyle(
                  fontSize: Schrift.text, fontWeight: FontWeight.w600)),
          subtitle: Text(text(wert)),
          value: an,
          onChanged: aenderbar
              ? (v) => onChanged(v ? FantasyLeague.remisGrenzeStandard : null)
              : null,
        ),
        if (an)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Abstand in Punkten',
                    style: TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (aenderbar)
                  WertStepper(
                    label: 'Abstand für Unentschieden',
                    value: erlaubt(wert!),
                    min: min,
                    max: max,
                    schritt: schritt,
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
