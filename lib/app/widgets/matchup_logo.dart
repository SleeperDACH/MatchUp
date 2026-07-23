import 'package:flutter/material.dart';

import '../theme.dart';
import 'matchup_chevron.dart';

/// MatchUp-Wortmarken-Logo: der zweifarbige Doppel-Chevron plus „Match" + „Up"
/// (Up in Grün). Skalierbar über [chevronSize]; als Zeile (Kopfzeile) oder
/// gestapelt (Hero/Anmeldung) einsetzbar.
class MatchUpLogo extends StatelessWidget {
  const MatchUpLogo({
    super.key,
    this.chevronSize = 22,
    this.fontSize,
    this.vertical = false,
    this.wordColor = MatchUpColors.snow,
  });

  /// Höhe des Chevrons in logischen Pixeln.
  final double chevronSize;

  /// Schriftgröße der Wortmarke; ohne Angabe aus [chevronSize] abgeleitet.
  final double? fontSize;

  /// Gestapelt (Chevron über der Wortmarke) statt nebeneinander.
  final bool vertical;

  /// Farbe des „Match"-Teils (Up bleibt grün). Standard: helles Snow.
  final Color wordColor;

  @override
  Widget build(BuildContext context) {
    final fs = fontSize ?? chevronSize * (vertical ? 0.52 : 0.92);
    final wordmark = Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fs,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: wordColor,
          height: 1.0,
        ),
        children: const [
          TextSpan(text: 'Match'),
          TextSpan(text: 'Up', style: TextStyle(color: MatchUpColors.green)),
        ],
      ),
    );
    final chevron = MatchUpChevron(size: chevronSize);

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          chevron,
          SizedBox(height: chevronSize * 0.30),
          wordmark,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        chevron,
        SizedBox(width: chevronSize * 0.36),
        wordmark,
      ],
    );
  }
}
