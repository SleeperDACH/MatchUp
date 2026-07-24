import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Standard-Profilbild für Konten ohne eigenes Bild/Emoji: ein Gesicht im Stil
/// der MatchUp-Marke — zwei „∧"-Chevron-Augen (wie die Logo-Chevrons) und ein
/// „∨"-Chevron-Lächeln, auf einem pro Nutzer eingefärbten Feld. Die Farbe wird
/// deterministisch aus [seed] abgeleitet, damit ein Nutzer immer dieselbe Farbe
/// hat (bis er ein eigenes Bild wählt).
class DefaultAvatar extends StatelessWidget {
  const DefaultAvatar({
    super.key,
    required this.seed,
    this.size = 44,
    this.cornerRadius,
  });

  /// Stabiler Schlüssel je Nutzer (User-ID bevorzugt, sonst Anzeigename).
  final String seed;
  final double size;

  /// `null` → Kreis (Profile); ein Wert → abgerundetes Quadrat.
  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final bg = defaultAvatarColor(seed);
    return CustomPaint(
      size: Size(size, size),
      painter: _FacePainter(bg: bg, cornerRadius: cornerRadius),
    );
  }
}

/// Kräftige, gut lesbare Farbpalette für das Standard-Avatar. Bewusst ohne
/// zu helle Töne; die Gesichtszüge werden je nach Helligkeit hell oder dunkel
/// gezeichnet (siehe [_FacePainter]).
const List<Color> kDefaultAvatarPalette = [
  Color(0xFF2E7DF6), // Blau
  Color(0xFF7C5CFF), // Violett
  Color(0xFFFF4FA3), // Pink
  Color(0xFFF51D1D), // Rot (Marke)
  Color(0xFFFF6A1A), // Orange
  Color(0xFF0FC5A6), // Türkis
  Color(0xFF22C55E), // Grün
  Color(0xFFF5A310), // Bernstein
  Color(0xFFFF3D77), // Rosé
  Color(0xFF12A9F0), // Himmel
  Color(0xFF9B2BFF), // Lila
  Color(0xFF4F46E5), // Indigo
];

/// Deterministische Farbwahl aus [seed] (FNV-1a-Hash über die Codepunkte),
/// damit dieselbe Person überall dieselbe Farbe bekommt.
Color defaultAvatarColor(String seed) {
  var h = 0x811c9dc5;
  for (final u in seed.codeUnits) {
    h ^= u;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return kDefaultAvatarPalette[h % kDefaultAvatarPalette.length];
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.bg, this.cornerRadius});

  final Color bg;
  final double? cornerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Rect.fromLTWH(0, 0, w, h);

    // Hintergrundfläche (Kreis oder abgerundetes Quadrat).
    final bgPaint = Paint()..color = bg;
    if (cornerRadius == null) {
      canvas.drawOval(rect, bgPaint);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius!)), bgPaint);
    }

    // Gesichtszüge hell auf dunklem Grund, dunkel auf hellem Grund.
    final lum = (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b);
    final markColor = lum > 0.62 ? MatchUpColors.base : MatchUpColors.snow;

    // Einheitskoordinaten (0..1), skaliert auf die Boxgröße.
    Offset p(double x, double y) => Offset(x * w, y * h);

    // Chevron als Polylinie. up=true → Enden oben, Mitte unten („∨", Lächeln);
    // up=false → Spitze oben, Enden unten („∧", Auge wie der Logo-Chevron).
    Path chevron(Offset c, double halfW, double halfH, {required bool up}) {
      final dy = up ? -halfH : halfH;
      return Path()
        ..moveTo(c.dx - halfW * w, c.dy + dy * h)
        ..lineTo(c.dx, c.dy - dy * h)
        ..lineTo(c.dx + halfW * w, c.dy + dy * h);
    }

    final face = Path()
      // Zwei ∧-Chevron-Augen wie die Logo-Chevrons (Spitze oben), weit auseinander
      ..addPath(chevron(p(0.32, 0.40), 0.09, 0.07, up: false), Offset.zero)
      ..addPath(chevron(p(0.68, 0.40), 0.09, 0.07, up: false), Offset.zero)
      // Breites ∨-Lächeln (Enden oben), deutlich tiefer für klare Gesichtslesart
      ..addPath(chevron(p(0.50, 0.70), 0.22, 0.06, up: true), Offset.zero);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = markColor
      ..strokeWidth = size.shortestSide * 0.10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(face, stroke);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) =>
      old.bg != bg || old.cornerRadius != cornerRadius;
}
