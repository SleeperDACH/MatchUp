import 'package:flutter/material.dart';

import '../../app/typografie.dart';

/// **Eine Einstellung, eine Zeile — überall gleich** (18.10.2026).
///
/// Gemeldet an „Fantasy-Liga erstellen" und „Tippspiel erstellen": „zu viel
/// Ungleichheit … das muss alles einheitlich aussehen". Dort standen drei
/// Titelgrößen nebeneinander, gerahmte Auswahlkästen neben nackten Zeilen,
/// Modus-Kacheln mit grünem Hauch und graue Kästen um Untereinstellungen.
///
/// Die Regel jetzt: Bezeichnung links in [einstellungsStil], Bedienung rechts
/// (Schalter, `WertStepper`, Text-Knopf), höchstens **eine** kurze Zeile
/// darunter, Zeilen mindestens 48 hoch und durch [EinstellungsTrenner]
/// getrennt. Kein Symbol davor, keine Fläche dahinter — Farbe trägt allein
/// der eingeschaltete Schalter.
const einstellungsStil =
    TextStyle(fontSize: Schrift.text, fontWeight: FontWeight.w600);

/// Bezeichnung links, Bedienung rechts, optional eine kurze Unterzeile.
class EinstellungsZeile extends StatelessWidget {
  const EinstellungsZeile({
    super.key,
    required this.label,
    required this.rechts,
    this.unter,
    this.vorne,
  });

  final String label;
  final Widget rechts;
  final String? unter;

  /// Ein Zeichen vor der Bezeichnung — nur, wo es die Auskunft ist (das
  /// Wappen eines Wettbewerbs), nicht als Schmuck.
  final Widget? vorne;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          if (vorne != null) ...[vorne!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: einstellungsStil),
                if (unter != null)
                  Text(
                    unter!,
                    style: TextStyle(
                      fontSize: Schrift.text,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          rechts,
        ],
      ),
    );
  }
}

/// Dieselbe Zeile mit Schalter. Die ganze Zeile nimmt den Tipp an.
/// `onChanged: null` = sichtbar, aber nicht änderbar.
class EinstellungsSchalter extends StatelessWidget {
  const EinstellungsSchalter({
    super.key,
    required this.label,
    required this.wert,
    required this.onChanged,
    this.unter,
  });

  final String label;
  final String? unter;
  final bool wert;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: wert,
        onChanged: onChanged,
        title: Text(label, style: einstellungsStil),
        subtitle: unter == null ? null : Text(unter!),
      );
}

/// Haarlinie zwischen zwei Zeilen eines Abschnitts.
class EinstellungsTrenner extends StatelessWidget {
  const EinstellungsTrenner({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
      );
}
