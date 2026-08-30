/// **Punktstände lesbar hinschreiben.**
///
/// Gemeldet: *„Die Zahlen der Punktstände sind doof zu lesen."* Zwei Ursachen,
/// die beide an der Zahl selbst liegen:
///
/// * **Die Nachkommastelle rief so laut wie die Zahl.** „128,4 : 99,5" zwingt
///   das Auge, vier Zeichen zu lesen, bevor es die Größenordnung hat — dabei
///   entscheidet die Zehntelstelle so gut wie nie etwas. Sie steht jetzt
///   kleiner und leiser hinter der Zahl: **128**,4. Weg ist sie nicht, denn bei
///   einem Vorsprung von 0,4 Punkten wäre „128 : 99" gelogen.
/// * **Die Ziffern waren verschieden breit.** In einem laufenden Spiel wandert
///   der Doppelpunkt dann bei jeder Aktualisierung hin und her.
///   `FontFeature.tabularFigures` gibt jeder Ziffer dieselbe Breite; damit
///   stehen auch Spalten untereinander (Tabelle, Aufstellung) ruhig.
library;

import 'package:flutter/material.dart';

import '../../features/fantasy/logic/fantasy_scoring_engine.dart';

/// Ziffern gleicher Breite — für jede Zahl, die sich ändert oder in einer
/// Spalte steht.
const List<FontFeature> gleichbreiteZiffern = [FontFeature.tabularFigures()];

class Punktzahl extends StatelessWidget {
  const Punktzahl(this.wert, {super.key, this.stil, this.bruchAnteil = 0.6});

  final double wert;

  /// Stil der **ganzen** Zahl. Der Bruchteil leitet sich daraus ab.
  final TextStyle? stil;

  /// Wie groß der Bruchteil im Verhältnis zur ganzen Zahl steht.
  final double bruchAnteil;

  /// **Erst ab dieser Schriftgröße lohnt die Zweiteilung.** In einer Listenzeile
  /// (14–16 Punkt) würde aus dem Bruchteil ein 9-Punkt-Krümel — schwerer zu
  /// lesen als vorher, nicht leichter. Dort bleibt die Zahl, wie sie ist; die
  /// gleichbreiten Ziffern bekommt sie trotzdem, denn dort steht sie in einer
  /// Spalte.
  static const kleinsteZweiteilung = 20.0;

  @override
  Widget build(BuildContext context) {
    final basis = (stil ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: gleichbreiteZiffern,
    );
    final text = formatPoints(wert);
    final komma = text.indexOf(',');
    if (komma < 0 || (basis.fontSize ?? 0) < kleinsteZweiteilung) {
      return Text(text, style: basis);
    }

    final klein = basis.fontSize == null
        ? basis
        : basis.copyWith(
            fontSize: basis.fontSize! * bruchAnteil,
            // Etwas leiser, aber nicht verschluckt: Wer genau hinsieht, muss
            // die Zehntel noch lesen können.
            color: (basis.color ?? Colors.white).withValues(alpha: 0.72),
          );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, komma), style: basis),
          TextSpan(text: text.substring(komma), style: klein),
        ],
      ),
      style: basis,
    );
  }
}
