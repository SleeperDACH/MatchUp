import 'package:flutter/material.dart';

import '../theme.dart';

/// Der Doppel-Chevron der MatchUp-Marke (linke Hälfte grün, rechte rot),
/// exakt nach den Koordinaten des Marken-SVGs gezeichnet. Wiederverwendbar
/// als Kopfzeilen-Logo und als Tab-Icon.
class MatchUpChevron extends StatelessWidget {
  const MatchUpChevron({super.key, required this.size, this.color});

  /// Höhe in logischen Pixeln (Breite folgt dem Seitenverhältnis).
  final double size;

  /// Wenn gesetzt, wird der gesamte Chevron einfarbig gezeichnet (statt
  /// grün|rot) — z. B. als dezentes, ausgegrautes Wasserzeichen im Hintergrund.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * _ChevronPainter.refW / _ChevronPainter.refH, size),
      painter: _ChevronPainter(color),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter([this.color]);

  /// Einfarbige Zeichnung, falls gesetzt — sonst grün|rot geteilt.
  final Color? color;

  // Referenz-Box um den Chevron (inkl. Platz für die runden Kappen),
  // entnommen aus dem Marken-SVG (viewBox 600×200).
  static const refW = 58.0; // x 164 … 222
  static const refH = 54.4; // y 73.4 … 127.8
  static const _ox = 164.0;
  static const _oy = 73.4;
  static const _centerX = 193.0; // Teilung Green|Red an der Spitze

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / refW;
    final sy = size.height / refH;
    Offset p(double x, double y) => Offset((x - _ox) * sx, (y - _oy) * sy);

    final path = Path()
      // oberer Chevron
      ..moveTo(p(169, 102.4).dx, p(169, 102.4).dy)
      ..lineTo(p(193, 78.4).dx, p(193, 78.4).dy)
      ..lineTo(p(217, 102.4).dx, p(217, 102.4).dy)
      // unterer Chevron
      ..moveTo(p(169, 122.8).dx, p(169, 122.8).dy)
      ..lineTo(p(193, 98.8).dx, p(193, 98.8).dy)
      ..lineTo(p(217, 122.8).dx, p(217, 122.8).dy);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0 * (sx + sy) / 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Einfarbige Variante (Wasserzeichen): kein grün|rot-Split.
    if (color != null) {
      canvas.drawPath(path, paint..color = color!);
      return;
    }

    final centerX = (_centerX - _ox) * sx;
    // Linke Hälfte grün.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, centerX, size.height));
    canvas.drawPath(path, paint..color = MatchUpColors.green);
    canvas.restore();
    // Rechte Hälfte rot.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(centerX, 0, size.width - centerX, size.height));
    canvas.drawPath(path, paint..color = MatchUpColors.red);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}
