import 'package:flutter/material.dart';

import '../../core/util/club_colors.dart';

/// Trikot mit Rückennummer, in den Farben des Vereins.
///
/// Ersetzt auf dem Spielfeld die früheren Kreise: Ein Trikot ist als Symbol
/// sofort als Spieler lesbar, und die Vereinsfarbe sagt schon vor dem Lesen
/// des Namens, welche Mannschaft da steht.
///
/// Gezeichnet statt als Bild geladen — bei 30 px Kantenlänge wäre jede Grafik
/// entweder unscharf oder unnötig groß, und die Farben müssen ohnehin je
/// Verein wechseln.
class JerseyIcon extends StatelessWidget {
  const JerseyIcon({
    super.key,
    required this.colors,
    this.number,
    this.size = 32,
  });

  final ClubColors colors;
  final int? number;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _JerseyPainter(colors),
        child: Center(
          // Etwas unterhalb der Mitte: Dort sitzt beim echten Trikot die
          // Rückennummer, oberhalb liegen Kragen und Schultern.
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.12),
            child: Text(
              number?.toString() ?? '',
              style: TextStyle(
                color: jerseyTextColor(colors.primary),
                fontWeight: FontWeight.w800,
                fontSize: size * 0.40,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JerseyPainter extends CustomPainter {
  _JerseyPainter(this.colors);
  final ClubColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double x(double f) => f * w;
    double y(double f) => f * h;

    // Ärmel links und rechts (liegen hinter dem Rumpf).
    final aermel = Path()
      ..moveTo(x(0.26), y(0.10))
      ..lineTo(x(0.02), y(0.32))
      ..lineTo(x(0.14), y(0.52))
      ..lineTo(x(0.30), y(0.38))
      ..close()
      ..moveTo(x(0.74), y(0.10))
      ..lineTo(x(0.98), y(0.32))
      ..lineTo(x(0.86), y(0.52))
      ..lineTo(x(0.70), y(0.38))
      ..close();

    // Rumpf: Schultern, leicht taillierte Seiten, gerader Saum.
    final rumpf = Path()
      ..moveTo(x(0.28), y(0.12))
      ..quadraticBezierTo(x(0.50), y(0.26), x(0.72), y(0.12))
      ..lineTo(x(0.78), y(0.34))
      ..lineTo(x(0.80), y(0.94))
      ..lineTo(x(0.20), y(0.94))
      ..lineTo(x(0.22), y(0.34))
      ..close();

    canvas.drawPath(aermel, Paint()..color = colors.secondary);
    canvas.drawPath(rumpf, Paint()..color = colors.primary);

    // Kragen in der Zweitfarbe — gibt dem Symbol auch bei einfarbigen Trikots
    // eine erkennbare Oberkante.
    final kragen = Path()
      ..moveTo(x(0.28), y(0.12))
      ..quadraticBezierTo(x(0.50), y(0.26), x(0.72), y(0.12))
      ..quadraticBezierTo(x(0.50), y(0.20), x(0.28), y(0.12))
      ..close();
    canvas.drawPath(kragen, Paint()..color = colors.secondary);

    // Feine dunkle Kontur, damit helle Trikots (Gladbach, Bielefeld) auf dem
    // grünen Rasen nicht ausfransen.
    final kontur = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..color = const Color(0x99000000);
    canvas.drawPath(aermel, kontur);
    canvas.drawPath(rumpf, kontur);
  }

  @override
  bool shouldRepaint(_JerseyPainter old) =>
      old.colors.primary != colors.primary ||
      old.colors.secondary != colors.secondary;
}
