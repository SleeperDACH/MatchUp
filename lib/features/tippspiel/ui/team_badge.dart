import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/models/models.dart';
import '../../../core/util/country_flags.dart';

/// Rundes Team-Badge: Länderflagge (über flagcdn, einheitlich) bzw.
/// Vereinslogo; Fallback sind die Initialen.
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.team, this.size = _size});

  final TeamRef team;
  final double size;

  static const _size = 28.0;

  @override
  Widget build(BuildContext context) {
    // Nationalteams: einheitliche Flagge, kreisförmig zugeschnitten.
    final flagUrl = countryFlagUrl(team.shortName);
    if (flagUrl != null) {
      return _circle(
        Image.network(
          flagUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _InitialsBadge(team: team, size: size),
        ),
      );
    }

    // Vereine: Logo (PNG oder SVG) im Kreis, mit Luft drumherum.
    final url = team.iconUrl;
    if (url != null) {
      final logo = url.toLowerCase().endsWith('.svg')
          ? SvgPicture.network(
              url,
              fit: BoxFit.contain,
              placeholderBuilder: (_) => const SizedBox.shrink(),
            )
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => _InitialsBadge(team: team, size: size),
            );
      return _circle(
        Container(
          color: Colors.white.withValues(alpha: 0.9),
          padding: const EdgeInsets.all(3),
          child: logo,
        ),
      );
    }

    return _InitialsBadge(team: team, size: size);
  }

  Widget _circle(Widget child) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: child),
    );
  }
}

class _InitialsBadge extends StatelessWidget {
  const _InitialsBadge({required this.team, this.size = TeamBadge._size});

  final TeamRef team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = team.shortName.length > 3
        ? team.shortName.substring(0, 3).toUpperCase()
        : team.shortName.toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: scheme.primary.withValues(alpha: 0.15),
      child: Text(initials,
          style: TextStyle(fontSize: size * 0.32, color: scheme.primary)),
    );
  }
}
