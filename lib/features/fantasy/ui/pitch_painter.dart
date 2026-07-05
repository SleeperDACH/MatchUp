import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zeichnet die Linien einer Fußballfeld-Hälfte: Außenlinie, Mittelkreis
/// (oben, halb), Straf- und Torraum samt Elfmeterpunkt und Bogen (unten, beim
/// Torwart). Liegt hinter den Spieler-Slots. Wird sowohl in der Aufstellung
/// (`LineupScreen`) als auch in der Kader-Übersicht des Draft-Raums genutzt.
class PitchLinesPainter extends CustomPainter {
  const PitchLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.fill;

    const inset = 8.0;
    final w = size.width;
    final h = size.height;
    final top = inset, bottom = h - inset;
    final cx = w / 2;

    // Außenlinie (oben = Mittellinie, unten = Torlinie).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(inset, top, w - inset, bottom),
          const Radius.circular(8)),
      line,
    );

    // Mittelkreis als unterer Halbbogen + Anstoßpunkt auf der Mittellinie.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, top), radius: w * 0.16),
      0,
      3.14159,
      false,
      line,
    );
    canvas.drawCircle(Offset(cx, top), 2.5, dot);

    // Strafraum unten (3 Seiten; Torlinie ist die Außenlinie).
    final paW = w * 0.58, paH = h * 0.20;
    void box(double bw, double bh) {
      canvas.drawPath(
        Path()
          ..moveTo(cx - bw / 2, bottom)
          ..lineTo(cx - bw / 2, bottom - bh)
          ..lineTo(cx + bw / 2, bottom - bh)
          ..lineTo(cx + bw / 2, bottom),
        line,
      );
    }

    box(paW, paH); // Strafraum
    box(w * 0.30, h * 0.09); // Torraum

    // Elfmeterpunkt + Strafraumbogen („D"): nur der Teil oberhalb der
    // Strafraumkante. Die Bogen-Enden treffen exakt auf die Kante — Winkel aus
    // dem Abstand Elfmeterpunkt→Kante und dem Radius berechnet.
    final penSpotY = bottom - paH * 0.62;
    canvas.drawCircle(Offset(cx, penSpotY), 2.5, dot);
    final arcR = w * 0.15;
    final boxTopOffset = penSpotY - (bottom - paH); // Abstand Punkt→Strafraumkante
    final a = math.asin((boxTopOffset / arcR).clamp(-1.0, 1.0));
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, penSpotY), radius: arcR),
      math.pi + a, // oben-links auf der Kante
      math.pi - 2 * a, // über den Scheitel bis oben-rechts auf der Kante
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Grüner Rasen-Verlauf für die Feld-Container (halbe Spielfeldhälfte).
const pitchGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
);
