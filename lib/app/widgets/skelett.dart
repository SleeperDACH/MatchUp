import 'dart:math' as math;

import 'package:flutter/material.dart';

/// **Die Form der Seite statt eines Ladekreises.**
///
/// Ein Kreis in der Mitte sagt nur „warte"; danach springt der Inhalt an
/// seinen Platz, und der Schirm baut sich zweimal auf. Das Skelett deutet
/// Zeilen an — Kreis für das Wappen oder Bild, zwei Balken für Name und
/// Zusatz —, und der echte Inhalt legt sich an dieselbe Stelle (Design-Ideen
/// Punkt 7, 15.10.2026).
///
/// **Es passt sich dem Platz an:** In begrenzter Höhe stehen so viele Zeilen,
/// wie hineinpassen, nie mehr — ein Skelett, das überläuft, wäre schlimmer
/// als der Kreis. Ohne Höhengrenze (in einer Spalte) sind es [zeilen].
///
/// Die Fläche atmet langsam (0,45 → 0,85 Deckkraft), statt zu glitzern: Ein
/// Schimmer quer über den Schirm ist die lauteste Bewegung, die es gibt, für
/// den langweiligsten Zustand.
class Skelett extends StatefulWidget {
  const Skelett({super.key, this.zeilen = 3, this.zeilenHoehe = 64});

  /// Zeilen, wenn die Höhe nicht begrenzt ist.
  final int zeilen;
  final double zeilenHoehe;

  @override
  State<Skelett> createState() => _SkelettState();
}

class _SkelettState extends State<Skelett> with SingleTickerProviderStateMixin {
  late final AnimationController _atem = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _atem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grund = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Wird geladen',
      child: LayoutBuilder(builder: (context, c) {
        final h = widget.zeilenHoehe;
        final anzahl = c.maxHeight.isFinite
            ? math.max(1, ((c.maxHeight - 16) / (h + 8)).floor())
            : widget.zeilen;
        final breite = c.maxWidth.isFinite ? c.maxWidth : 240.0;
        return ClipRect(
          child: FadeTransition(
            opacity: Tween(begin: 0.45, end: 0.85).animate(_atem),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < anzahl; i++)
                    _Zeile(
                      hoehe: h,
                      breite: breite - 24,
                      farbe: grund,
                      // Leicht verschieden lange Balken — gleich lange sähen
                      // aus wie ein Muster, nicht wie Inhalt.
                      anteil: const [0.62, 0.48, 0.7, 0.55][i % 4],
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.hoehe,
    required this.breite,
    required this.farbe,
    required this.anteil,
  });

  final double hoehe;
  final double breite;
  final Color farbe;
  final double anteil;

  @override
  Widget build(BuildContext context) {
    Widget balken(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: farbe.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(h / 2),
          ),
        );
    final textBreite = math.max(0.0, breite - 56);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: hoehe,
        width: breite,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: farbe.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  balken(textBreite * anteil, 12),
                  const SizedBox(height: 8),
                  balken(textBreite * anteil * 0.6, 9),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
