import 'package:flutter/material.dart';

import '../typografie.dart';

/// **Erklärung auf Nachfrage, nicht im Bild.**
///
/// Unter Tabellen, über Listen und neben Zahlen standen Sätze, die eine Regel
/// erklärten („3 Punkte für einen Sieg …", „Waiver bis Mo — dann werden die
/// Anträge nach Priorität vergeben …"). Sie sind richtig und werden genau
/// einmal gelesen; danach sind sie Fläche, die jeden Besuch kostet. Seit dem
/// 15.10.2026 (Design-Ideen Punkt 4) steht dort nur noch die Auskunft, und
/// die Regel liegt hinter diesem Knopf.
///
/// Ein Tipp öffnet ein Blatt mit [titel] und [text]. Die Tastfläche ist
/// 44 Punkte groß, das Symbol klein und grau — es soll da sein, nicht rufen.
class InfoKnopf extends StatelessWidget {
  const InfoKnopf({
    super.key,
    required this.titel,
    required this.text,
    this.groesse = 18,
    this.frage = false,
    this.farbe,
  });

  final String titel;
  final String text;
  final double groesse;

  /// **Fragezeichen statt ⓘ** — für „Was ist das?" an Begriffen, die ein
  /// neuer Nutzer nicht kennt (Fantasy, Tippspiel, Globales Tippspiel).
  /// Das ⓘ bleibt für Regeln an Zahlen und Listen.
  final bool frage;

  /// Symbolfarbe, wenn der Grund nicht der App-Grund ist (die Startkarten
  /// mit Foto sind in beiden Modi dunkel). Sonst das leise Grau.
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Erklärung: $titel',
      onPressed: () => zeigeErklaerung(context, titel: titel, text: text),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      icon: Icon(
        frage ? Icons.help_outline : Icons.info_outline,
        size: groesse,
        color: farbe ?? scheme.onSurfaceVariant,
      ),
    );
  }
}

/// Das Blatt hinter dem [InfoKnopf] — auch direkt aufrufbar.
Future<void> zeigeErklaerung(
  BuildContext context, {
  required String titel,
  required String text,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Abstand.l, 0, Abstand.l, Abstand.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titel,
              style: Theme.of(
                ctx,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: Abstand.s),
            Text(
              text,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
