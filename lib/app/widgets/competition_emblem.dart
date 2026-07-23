import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Eigenes, MatchUp-angelehntes Wettbewerbs-Emblem (Vektor, keine fremden
/// Logos): Globus für Turniere (WM/EM), Fußball für Vereinsligen, sonst das
/// MatchUp-Chevron. Dunkles, abgerundetes Badge mit grün/rot/snow-Akzenten.
class CompetitionEmblem extends StatelessWidget {
  const CompetitionEmblem({super.key, required this.leagueId, this.size = 40});

  final String leagueId;
  final double size;

  _Glyph get _glyph => switch (leagueId) {
        'wm2026' => _Glyph.globe,
        'bundesliga' ||
        'bundesliga2' ||
        'liga3' ||
        'dfb_pokal' ||
        'frauen_bundesliga' =>
          _Glyph.football,
        _ => _Glyph.chevron,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2230), MatchUpColors.base],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: CustomPaint(painter: _EmblemPainter(_glyph)),
    );
  }
}

enum _Glyph { globe, football, chevron }

class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.glyph);

  final _Glyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.width;
    switch (glyph) {
      case _Glyph.globe:
        _globe(canvas, c, s);
      case _Glyph.football:
        _football(canvas, c, s);
      case _Glyph.chevron:
        _chevron(canvas, c, s);
    }
  }

  void _globe(Canvas canvas, Offset c, double s) {
    final r = s * 0.30;
    final line = Paint()
      ..color = MatchUpColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.045
      ..strokeCap = StrokeCap.round;
    // Globus: Kreis, Äquator und ein Meridian (vertikale Ellipse).
    canvas.drawCircle(c, r, line);
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), line);
    canvas.drawOval(
        Rect.fromCenter(center: c, width: r, height: 2 * r), line);
    // Snow-Breitenkreis oberhalb des Äquators.
    final thin = Paint()
      ..color = MatchUpColors.snow.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(c.dx - r * 0.82, c.dy - r * 0.52),
        Offset(c.dx + r * 0.82, c.dy - r * 0.52), thin);
    // Roter Akzent als „Ball im Orbit".
    canvas.drawCircle(Offset(c.dx + r * 0.95, c.dy - r * 0.95), s * 0.055,
        Paint()..color = MatchUpColors.red);
  }

  void _football(Canvas canvas, Offset c, double s) {
    final r = s * 0.30;
    // Ball: heller Kreis mit grünem Rand.
    canvas.drawCircle(c, r, Paint()..color = MatchUpColors.snow);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = MatchUpColors.green
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04);
    // Mittiges Fünfeck.
    final rp = r * 0.45;
    final pent = <Offset>[
      for (var i = 0; i < 5; i++)
        Offset(
          c.dx + rp * math.cos(-math.pi / 2 + i * 2 * math.pi / 5),
          c.dy + rp * math.sin(-math.pi / 2 + i * 2 * math.pi / 5),
        ),
    ];
    final path = Path()..addPolygon(pent, true);
    canvas.drawPath(path, Paint()..color = MatchUpColors.green);
    // Nähte von den Ecken nach außen.
    final seam = Paint()
      ..color = MatchUpColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * rp, c + dir * (r * 0.92), seam);
    }
  }

  void _chevron(Canvas canvas, Offset c, double s) {
    void arrow(double dy, Color color, double scale) {
      final w = s * 0.20 * scale;
      final h = s * 0.13 * scale;
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.05
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - w, c.dy + dy + h)
          ..lineTo(c.dx, c.dy + dy)
          ..lineTo(c.dx + w, c.dy + dy + h),
        p,
      );
    }

    // Zwei aufsteigende Chevrons (grün groß, rot klein) — MatchUp-Marke.
    arrow(s * 0.10, MatchUpColors.green, 1.2);
    arrow(-s * 0.10, MatchUpColors.red, 0.8);
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter old) => old.glyph != glyph;
}
