import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/util/club_logos.dart';

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
