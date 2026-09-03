import 'package:flutter/material.dart';

import '../../core/util/club_colors.dart';

/// Trikot mit Rückennummer, in den Farben des Vereins.
///
/// Ersetzt auf den Spielfeldern die früheren Kreise: Ein Trikot ist als Symbol
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
            padding: EdgeInsets.only(top: size * 0.20),
            child: Text(
              number?.toString() ?? '',
              style: TextStyle(
                color: jerseyTextColor(colors.primary),
                fontWeight: FontWeight.w800,
                fontSize: size * 0.36,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// **Ein Umriss, keine zusammengesetzten Kästchen.**
///
/// Der erste Wurf zeichnete Ärmel und Rumpf als getrennte Vielecke und zog um
/// beide eine Kontur — dort, wo die Ärmel unter dem Rumpf verschwanden, blieben
/// die Linien sichtbar. Gemeldet als „das sieht aus wie Kästchen aneinander,
/// diese Kanten, die sich überschneiden".
///
/// Jetzt ist das Trikot **ein einziger geschlossener Pfad**: Halsausschnitt,
/// Schultern, Ärmel, Seiten und Saum in einem Zug, mit runden Ecken. Alles
/// Weitere (kontrastfarbene Ärmel, Kragen) wird **in diesen Pfad hinein**
/// geclippt und kann deshalb keine eigene Kante zeigen.
class _JerseyPainter extends CustomPainter {
  _JerseyPainter(this.colors);
  final ClubColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    double x(double f) => f * w;
    double y(double f) => f * h;

    // Klassischer Trikot-Umriss von vorn: schmaler Halsausschnitt, schräge
    // Schultern, kurze angesetzte Ärmel, gerader Saum mit runden Ecken. Die
    // Zahlen sind Anteile der Kantenlänge, damit das Symbol in jeder Größe
    // gleich aussieht. **Kurze Kurven an den Ecken, keine großen Bögen** —
    // der erste Anlauf war so rund, dass die Ärmel wie zwei Ballons neben
    // einem schmalen Rumpf saßen.
    final trikot = Path()
      // linker Halspunkt → Schulter → Ärmel außen → Ärmelsaum → Achsel
      ..moveTo(x(0.40), y(0.13))
      ..lineTo(x(0.31), y(0.15))
      ..quadraticBezierTo(x(0.16), y(0.19), x(0.05), y(0.31))
      ..quadraticBezierTo(x(0.03), y(0.34), x(0.05), y(0.37))
      ..lineTo(x(0.13), y(0.48))
      ..quadraticBezierTo(x(0.15), y(0.51), x(0.18), y(0.49))
      ..lineTo(x(0.23), y(0.44))
      // Rumpf: linke Seite, Saum mit runden Ecken, rechte Seite
      ..lineTo(x(0.22), y(0.87))
      ..quadraticBezierTo(x(0.22), y(0.92), x(0.27), y(0.92))
      ..lineTo(x(0.73), y(0.92))
      ..quadraticBezierTo(x(0.78), y(0.92), x(0.78), y(0.87))
      ..lineTo(x(0.77), y(0.44))
      // rechte Achsel → Ärmelsaum → Ärmel außen → Schulter → Halspunkt
      ..lineTo(x(0.82), y(0.49))
      ..quadraticBezierTo(x(0.85), y(0.51), x(0.87), y(0.48))
      ..lineTo(x(0.95), y(0.37))
      ..quadraticBezierTo(x(0.97), y(0.34), x(0.95), y(0.31))
      ..quadraticBezierTo(x(0.84), y(0.19), x(0.69), y(0.15))
      ..lineTo(x(0.60), y(0.13))
      // Halsausschnitt
      ..quadraticBezierTo(x(0.57), y(0.25), x(0.50), y(0.25))
      ..quadraticBezierTo(x(0.43), y(0.25), x(0.40), y(0.13))
      ..close();

    // Grundfarbe.
    canvas.drawPath(trikot, Paint()..color = colors.primary);

    // **Die Ärmel sind Ärmel, keine Rechtecke.** Der Anlauf davor legte zwei
    // Rechtecke über die oberen Ecken und schnitt sie am Umriss ab — die
    // Innenkante blieb dabei eine kerzengerade Senkrechte quer durch den
    // Rumpf, und genau die las sich als „Kästchen aneinander". Jetzt trägt
    // jeder Ärmel seinen eigenen Pfad: außen die Kontur des Trikots, innen
    // die Schulternaht von der Achsel zurück zum Hals. Eine schräge Naht, wie
    // an einem echten Trikot, und keine Kante, die irgendwo endet.
    final zweit = Paint()..color = colors.secondary;
    canvas.drawPath(
      Path()
        ..moveTo(x(0.31), y(0.15))
        ..quadraticBezierTo(x(0.16), y(0.19), x(0.05), y(0.31))
        ..quadraticBezierTo(x(0.03), y(0.34), x(0.05), y(0.37))
        ..lineTo(x(0.13), y(0.48))
        ..quadraticBezierTo(x(0.15), y(0.51), x(0.18), y(0.49))
        ..lineTo(x(0.23), y(0.44))
        ..close(),
      zweit,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x(0.69), y(0.15))
        ..quadraticBezierTo(x(0.84), y(0.19), x(0.95), y(0.31))
        ..quadraticBezierTo(x(0.97), y(0.34), x(0.95), y(0.37))
        ..lineTo(x(0.87), y(0.48))
        ..quadraticBezierTo(x(0.85), y(0.51), x(0.82), y(0.49))
        ..lineTo(x(0.77), y(0.44))
        ..close(),
      zweit,
    );

    // Kragenband: der Halsausschnitt als schmale Linie. Es liegt **innerhalb**
    // des Umrisses (geclippt), sonst stünde es oben über die Schultern hinaus.
    canvas.save();
    canvas.clipPath(trikot);
    canvas.drawPath(
      Path()
        ..moveTo(x(0.40), y(0.13))
        ..quadraticBezierTo(x(0.43), y(0.25), x(0.50), y(0.25))
        ..quadraticBezierTo(x(0.57), y(0.25), x(0.60), y(0.13)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.05
        ..color = colors.secondary,
    );
    canvas.restore();

    // Eine feine Kontur außen — damit helle Trikots (Gladbach, Bielefeld) auf
    // hellem Rasen nicht ausfransen. Runde Ecken und Verbindungen, sonst
    // stechen die Kurvenenden als Spitzen heraus.
    canvas.drawPath(
      trikot,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x8C000000),
    );
  }

  @override
  bool shouldRepaint(_JerseyPainter old) =>
      old.colors.primary != colors.primary ||
      old.colors.secondary != colors.secondary;
}
