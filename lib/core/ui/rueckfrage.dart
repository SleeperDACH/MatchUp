import 'package:flutter/material.dart';

import '../../app/typografie.dart';

/// **Eine Rückfrage — als Blatt, nicht als Kasten** (19.10.2026, auf Ansage:
/// „wieder dieses komische Box-Design, das wir nicht mehr haben möchten").
///
/// Der Material-`AlertDialog` war ein grauer Kasten mitten im Bild mit zwei
/// kleinen Textknöpfen unten rechts. Die Rückfragen dieser App stehen jetzt
/// in derselben Form wie „Draft starten?": ein Blatt von unten, der Titel
/// schräg in Versalien, ein Satz, optional ein eigener Inhalt, darunter die
/// Knöpfe groß in voller Breite.
///
/// [gefahr] färbt den Bestätigungsknopf rot (Löschen, Verlassen, Droppen);
/// [farbe] setzt eine eigene (Gold beim Draft). Liefert `true` nur, wenn
/// bestätigt wurde — Wischen und „Abbrechen" sind `false`.
Future<bool> rueckfrage(
  BuildContext context, {
  required String titel,
  String? text,
  Widget? inhalt,
  required String ja,
  String nein = 'Abbrechen',
  bool gefahr = false,
  Color? farbe,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) => RueckfrageBlatt(
      titel: titel,
      text: text,
      inhalt: inhalt,
      ja: ja,
      nein: nein,
      gefahr: gefahr,
      farbe: farbe,
    ),
  );
  return ok == true;
}

/// Der Inhalt von [rueckfrage] — öffentlich, damit Vorschauen ihn zeigen
/// können.
class RueckfrageBlatt extends StatelessWidget {
  const RueckfrageBlatt({
    super.key,
    required this.titel,
    required this.ja,
    this.text,
    this.inhalt,
    this.nein = 'Abbrechen',
    this.gefahr = false,
    this.farbe,
  });

  final String titel;
  final String? text;
  final Widget? inhalt;
  final String ja;
  final String nein;
  final bool gefahr;
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const hoch = Size.fromHeight(50);
    final knopfFarbe = farbe ?? (gefahr ? scheme.error : null);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 24, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titel.toUpperCase(),
              style: const TextStyle(
                fontSize: Schrift.gross,
                fontWeight: Schrift.ueberschriftGewicht,
                fontStyle: Schrift.ueberschriftStil,
                height: 1.15,
              ),
            ),
            if (text != null) ...[
              const SizedBox(height: 10),
              Text(
                text!,
                style: TextStyle(
                  fontSize: Schrift.text,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (inhalt != null) ...[
              const SizedBox(height: 16),
              inhalt!,
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: hoch,
                backgroundColor: knopfFarbe,
                foregroundColor: knopfFarbe == null ? null : scheme.surface,
              ),
              child: Text(ja),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                minimumSize: hoch,
                foregroundColor: scheme.onSurfaceVariant,
              ),
              child: Text(nein),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ein Knopf einer Rückfrage mit mehreren Wegen.
class RueckfrageKnopf<T> {
  const RueckfrageKnopf(this.wert, this.wort, {this.gefahr = false});

  final T wert;
  final String wort;

  /// Rot — der Weg, der etwas zerstört.
  final bool gefahr;
}

/// Eine Rückfrage mit **mehreren Wegen** (etwa „Tippspiel behalten" oder
/// „Beides löschen"). Der erste Knopf ist der gefüllte, die weiteren stehen
/// mit Haarlinie darunter, „Abbrechen" ganz unten. Liefert den Wert des
/// gewählten Knopfs oder `null`.
Future<T?> rueckfrageWahl<T>(
  BuildContext context, {
  required String titel,
  String? text,
  required List<RueckfrageKnopf<T>> knoepfe,
  String nein = 'Abbrechen',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      const hoch = Size.fromHeight(50);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                titel.toUpperCase(),
                style: const TextStyle(
                  fontSize: Schrift.gross,
                  fontWeight: Schrift.ueberschriftGewicht,
                  fontStyle: Schrift.ueberschriftStil,
                  height: 1.15,
                ),
              ),
              if (text != null) ...[
                const SizedBox(height: 10),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: Schrift.text,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              for (final (i, k) in knoepfe.indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                if (i == 0)
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(k.wert),
                    style: FilledButton.styleFrom(
                      minimumSize: hoch,
                      backgroundColor: k.gefahr ? scheme.error : null,
                      foregroundColor: k.gefahr ? scheme.surface : null,
                    ),
                    child: Text(k.wort),
                  )
                else
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(k.wert),
                    style: OutlinedButton.styleFrom(
                      minimumSize: hoch,
                      foregroundColor:
                          k.gefahr ? scheme.error : scheme.onSurface,
                      side: BorderSide(color: Theme.of(ctx).dividerColor),
                    ),
                    child: Text(k.wort),
                  ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  minimumSize: hoch,
                  foregroundColor: scheme.onSurfaceVariant,
                ),
                child: Text(nein),
              ),
            ],
          ),
        ),
      );
    },
  );
}
