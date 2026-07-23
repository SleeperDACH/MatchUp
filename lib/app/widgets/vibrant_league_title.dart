import 'package:flutter/material.dart';

import '../../core/ui/app_avatar.dart';

/// Auffällige Liga-/Runden-Kopfzeile für die AppBar: das Logo/Emblem plus der
/// Name in fetter, condensed Schrift mit lebendigem Farbverlauf. Ersetzt die
/// schlichte `Text(name)`-Standardüberschrift.
class VibrantLeagueTitle extends StatelessWidget {
  const VibrantLeagueTitle({
    super.key,
    required this.name,
    this.subtitle,
    this.logoUrl,
    this.logoEmoji,
    this.logoColor,
  });

  final String name;
  final String? subtitle;
  final String? logoUrl;
  final String? logoEmoji;
  final String? logoColor;

  @override
  Widget build(BuildContext context) {
    final hasLogo = (logoUrl != null && logoUrl!.isNotEmpty) ||
        (logoEmoji != null && logoEmoji!.isNotEmpty);
    final title = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        // BarlowCondensed (App-Font) in maximaler Fettung → „dick" & sportlich.
        fontWeight: FontWeight.w800,
        fontSize: 25,
        letterSpacing: -0.4,
        height: 1.0,
        color: Colors.white,
      ),
    );

    final textBlock = subtitle == null
        ? title
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
              ),
            ],
          );

    if (!hasLogo) return textBlock;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppAvatar(
          imageUrl: logoUrl,
          emoji: logoEmoji,
          colorHex: logoColor,
          fallbackText: name,
          size: 32,
          cornerRadius: 9,
        ),
        const SizedBox(width: 10),
        Flexible(child: textBlock),
      ],
    );
  }
}
