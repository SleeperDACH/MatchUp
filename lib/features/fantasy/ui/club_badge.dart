import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/util/club_logos.dart';
import '../models/fantasy_models.dart';

/// Positionsfarben: TW blau, ABW gelb, MF grün, ST rot.
Color positionColor(PlayerPosition pos) => switch (pos) {
      PlayerPosition.gk => const Color(0xFF5B9DF9),
      PlayerPosition.def => const Color(0xFFFFC83D),
      PlayerPosition.mid => const Color(0xFF4ADE6A),
      PlayerPosition.fwd => const Color(0xFFF23030),
    };

/// Vereinslogo als flächenfüllender Hintergrund (BoxFit.cover). Ohne Logo
/// bleibt der Bereich leer (der darunterliegende Karten-Hintergrund zeigt sich).
/// [blurSigma] > 0 zeichnet das Logo weich — so wirken auch niedrig aufgelöste
/// oder quadratisch beschnittene Wappen als sauberer Farb-Backdrop.
class ClubLogoBackground extends StatelessWidget {
  const ClubLogoBackground({
    super.key,
    required this.club,
    this.iconUrl,
    this.blurSigma = 0,
  });

  final String club;
  final String? iconUrl;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final url = clubLogoUrl(club, iconUrl);
    if (url == null) return const SizedBox.expand();
    final Widget logo = url.toLowerCase().endsWith('.svg')
        ? SvgPicture.network(
            url,
            fit: BoxFit.cover,
            placeholderBuilder: (_) => const SizedBox.expand(),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          );
    if (blurSigma <= 0) return logo;
    // Etwas über die Kante skalieren, damit der Weichzeichner keine
    // durchscheinenden Ränder erzeugt; der Rest wird von der Karte geclippt.
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
            sigmaX: blurSigma, sigmaY: blurSigma, tileMode: TileMode.clamp),
        child: Transform.scale(scale: 1.2, child: logo),
      ),
    );
  }
}

/// Kleine, farbige Positions-Pille (TW/ABW/MF/ST).
class PositionPill extends StatelessWidget {
  const PositionPill({super.key, required this.pos});

  final PlayerPosition pos;

  @override
  Widget build(BuildContext context) {
    final color = positionColor(pos);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        pos.short,
        style: TextStyle(
          color: pos == PlayerPosition.def ? Colors.black : Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Vereinslogo eines Spielers anhand des (kanonischen OpenLigaDB-)Vereinsnamens.
/// [iconUrl] ist die vom Feed gelieferte Team-Icon-URL (aus der Tabelle
/// aufgelöst, siehe `clubIconsProvider`); ohne Treffer greifen die Overrides
/// aus [clubLogoUrl], sonst die Vereinsinitialen.
class ClubBadge extends StatelessWidget {
  const ClubBadge({
    super.key,
    required this.club,
    this.iconUrl,
    this.size = 28,
  });

  final String club;
  final String? iconUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = clubLogoUrl(club, iconUrl);
    if (url != null) {
      final logo = url.toLowerCase().endsWith('.svg')
          ? SvgPicture.network(
              url,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => _initials(context),
            )
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _initials(context),
            );
      return SizedBox(
        width: size,
        height: size,
        child: Padding(padding: EdgeInsets.all(size * 0.06), child: logo),
      );
    }
    return _initials(context);
  }

  Widget _initials(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary.withValues(alpha: 0.15),
      ),
      child: Text(
        _abbrev(club),
        style: TextStyle(
            fontSize: size * 0.3,
            color: scheme.primary,
            fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Kürzel aus dem Vereinsnamen: aus zwei Wörtern die Anfangsbuchstaben
  /// (z. B. „Borussia Dortmund" → „BD"), sonst die ersten Buchstaben.
  static String _abbrev(String club) {
    final words = club
        .replaceAll(RegExp(r'[0-9.]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length >= 2) {
      return (words[0][0] + words[1][0]).toUpperCase();
    }
    if (words.isNotEmpty) {
      final w = words.first;
      return w.substring(0, w.length < 3 ? w.length : 3).toUpperCase();
    }
    return '?';
  }
}
