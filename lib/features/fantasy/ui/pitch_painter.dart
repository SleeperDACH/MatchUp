import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Zeichnet die Linien einer Fußballfeld-Hälfte: Außenlinie, Mittelkreis
/// (oben, halb), Straf- und Torraum samt Elfmeterpunkt und Bogen (unten, beim
/// Torwart). Liegt hinter den Spieler-Slots. Wird sowohl in der Aufstellung
/// (`LineupScreen`) als auch in der Kader-Übersicht des Draft-Raums genutzt.
class PitchLinesPainter extends CustomPainter {
  const PitchLinesPainter({this.mitStreifen = true});

  /// Mähstreifen unter den Linien. In sehr kleinen Feldern (Draft-Raum,
  /// Manager-Profil) sind sechs Bahnen auf 200 Punkten Höhe Unruhe statt
  /// Struktur — dort bleiben sie aus.
  final bool mitStreifen;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 8.0;
    final w = size.width;
    final h = size.height;
    final top = inset, bottom = h - inset;
    final cx = w / 2;

    // **Mähstreifen.** Sechs Bahnen quer, abwechselnd eine Spur heller — mehr
    // ist es nicht, und mehr darf es auch nicht sein: Über den Streifen stehen
    // Wappen, Namen und Zahlen, und die Fläche ist ihr Grund, nicht ihr
    // Gegenstand.
    // **Zwei Lichtkegel von oben.** Sie sind der Grund, warum die Fläche
    // überhaupt nach Stadion aussieht und nicht nach grünem Rechteck —
    // dieselbe Sprache wie die Kopfkarte des Startbildschirms.
    if (mitStreifen) {
      for (final x in [w * 0.16, w * 0.84]) {
        canvas.drawCircle(
          Offset(x, -h * 0.12),
          h * 0.55,
          Paint()
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.13),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(
                Rect.fromCircle(center: Offset(x, -h * 0.12), radius: h * 0.55)),
        );
      }
    }

    if (mitStreifen) {
      final bahn = h / 6;
      final hell = Paint()..color = Colors.white.withValues(alpha: 0.035);
      for (var i = 0; i < 6; i += 2) {
        canvas.drawRect(Rect.fromLTWH(0, i * bahn, w, bahn), hell);
      }
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final dot = Paint()
      ..color = Colors.white.withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;

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
  bool shouldRepaint(covariant PitchLinesPainter oldDelegate) =>
      oldDelegate.mitStreifen != mitStreifen;
}

/// **Der Rasen bei Flutlicht.**
///
/// Vorher ein flacher Verlauf von Dunkelgrün nach Mittelgrün — ein Rechteck
/// Farbe, auf dem weiße Namen und helle Wappen um Kontrast kämpften. Jetzt
/// fällt das Licht von oben ein, wie auf der Kopfkarte des Startbildschirms:
/// in der Mitte oben ein beleuchteter Kern, zu den Rändern hin fast schwarz.
///
/// Das ist kein Schmuck, sondern der Grund für alles darauf: Auf einer Fläche,
/// die außen dunkel ist, stehen die Spieler an den Seitenlinien genauso lesbar
/// da wie die in der Mitte.
const pitchGradient = RadialGradient(
  center: Alignment(0, -0.62),
  radius: 0.98,
  colors: [
    Color(0xFF2E7D46),
    Color(0xFF1A5730),
    Color(0xFF0C3319),
    Color(0xFF04150A),
  ],
  stops: [0.0, 0.34, 0.68, 1.0],
);
