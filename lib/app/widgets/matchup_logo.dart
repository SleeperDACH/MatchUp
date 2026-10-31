import '../farben.dart';
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
    this.versal = false,
  });

  /// „MATCHUP" in Versalien und kursiv — wie im Kopf der App und auf dem
  /// Ladeschirm (31.10.2026, auf Ansage für den Anmeldeschirm).
  final bool versal;

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
          fontStyle: versal ? FontStyle.italic : null,
          letterSpacing: versal ? 0.4 : -0.5,
          color: wordColor,
          height: 1.0,
        ),
        children: [
          TextSpan(text: versal ? 'MATCH' : 'Match'),
          TextSpan(
            text: versal ? 'UP' : 'Up',
            style: TextStyle(color: context.farben.gruen),
          ),
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
