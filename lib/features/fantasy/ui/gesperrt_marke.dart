import 'package:flutter/material.dart';

/// **Ein Schloss statt eines Farbpunkts** — die Marke unter einem Spieler auf
/// einem Feld, das man nicht bearbeiten kann.
///
/// Dort stand ein 9 Punkt großer Kreis in der Positionsfarbe. Er sagte damit
/// zweierlei gleichzeitig und beides schlecht: Als **Positionshinweis** war er
/// überflüssig — auf einem Spielfeld sagt die Reihe, wer Torwart und wer
/// Stürmer ist —, und als **Zustandshinweis** sagte er gar nichts, weil er
/// genauso aussah wie ein Schmuckpunkt. Gemeldet als „wenn die Kader nicht
/// mehr bearbeitet werden können, ist dort nur noch ein Punkt in der Farbe der
/// Position; das möchte ich als Schloss und alles einfarbig".
///
/// **Einfarbig ist hier keine Sparsamkeit, sondern die Aussage.** Vier
/// Positionsfarben nebeneinander lesen sich als Gliederung; elf gleiche
/// Schlösser lesen sich als ein Zustand, der für alle gilt. Und es ist
/// dieselbe Marke, die der Aufstellungs-Editor schon zeigt, wenn ein Spiel
/// angepfiffen hat — zwei Wege in denselben Zustand sollen nicht verschieden
/// aussehen.
class GesperrtMarke extends StatelessWidget {
  const GesperrtMarke({super.key, this.size = 22});

  /// Kantenlänge des Kreises. Das Schloss darin folgt ihr.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Icon(
        Icons.lock,
        size: size * 0.5,
        color: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }
}
