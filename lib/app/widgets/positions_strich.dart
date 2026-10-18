import 'package:flutter/material.dart';

/// **Die Position als Strich, nicht als Fläche.**
///
/// Positionsfarben lagen als Verlauf oder volle Fläche unter Spielerkarten,
/// Kacheln und Pillen. Auf einem Schirm mit elf Spielern ergab das vier
/// Farbtöne nebeneinander, die alle gleich laut riefen — und keiner davon
/// hieß „gut", „schlecht" oder „läuft". Seit dem 15.10.2026 (Design-Ideen
/// Punkt 3) trägt Farbe in dieser App nur Bedeutung: **Grün ich/gut, Rot
/// live/schlecht, alles andere grau.** Die Position bleibt erkennbar, aber
/// leise: als 3 Punkte breiter Strich an der Außenkante der Karte.
///
/// Der Strich sitzt **in** der Karte und schiebt den Inhalt nicht — dieselbe
/// Bauart wie die Medaillenkante in der Tabelle (siehe CLAUDE.md, „Das Podest
/// steht oben").
class PositionsStrich extends StatelessWidget {
  const PositionsStrich({
    super.key,
    required this.farbe,
    required this.child,
    this.links = true,
  });

  final Color farbe;
  final Widget child;

  /// An welcher Kante der Strich steht — die Gastseite im MatchUp liest sich
  /// von rechts.
  final bool links;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 10,
          bottom: 10,
          left: links ? 0 : null,
          right: links ? null : 0,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: farbe,
              borderRadius: BorderRadius.horizontal(
                left: links ? Radius.zero : const Radius.circular(2),
                right: links ? const Radius.circular(2) : Radius.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
