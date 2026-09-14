import 'package:flutter/material.dart';

/// **Eine Kartenhülle für alle.**
///
/// Auf der Liga-Übersicht standen drei Sorten Karten untereinander, und jede
/// fasste ihre Kante anders: der MatchUp-Kasten mit einem roten Rand bei
/// 45 % Deckung, die Recap-Karte mit goldenem Rand **auf goldener Fläche**,
/// die Zeilengruppen mit einer grauen Haarlinie. Drei Behandlungen für
/// dieselbe Sorte Objekt — und die beiden lauten sahen aus, als sei dort etwas
/// zu tun, wo nur etwas zu lesen war.
///
/// **Tiefe entsteht auf dunklem Grund über die Fläche, nicht über die Kante.**
/// Deshalb: überall dieselbe Haarlinie, und der Unterschied liegt in der
/// Flächenstufe ([stufe]). Die Leiter dafür steht seit dem Aufräumen der
/// Farbschema-Flächen neutral im Theme (`surfaceContainer*`) — vorher hätte
/// dieser Ansatz gar nicht funktioniert, weil die Stufen grün gestochen waren.
///
/// Farbe trägt eine Karte nur als [hauch]: ein Schimmer aus der oberen linken
/// Ecke, bei drei Vierteln der Diagonale verklungen — dasselbe Muster wie bei
/// den Ligakarten auf dem Startbildschirm. Sie sagt „das gehört zu diesem
/// Bereich", nicht „hier musst du hin".
/// **Die Kartendekoration als eine Funktion** — Fläche, Hauch, Haarlinie.
///
/// Sie steht hier und nicht nur in [Karte], weil die Regel auch für Kästen
/// gilt, die keine `Karte` sein können: eine Hinweiszeile mit eigenem Polster,
/// ein Urteil, das im ruhigen Fall gar keine Fläche trägt. Die hatten alle
/// dasselbe Muster — **getönte Fläche plus farbiger Rand** —, und genau das
/// verbietet „Eine Kante für alle Karten". Gemeldet am 08.09.2026 an der
/// goldenen Umrandung im Aufstellungsreiter und an den Kacheln der
/// Liga-Übersicht.
///
/// [hauch] `null` heißt: keine Farbe, nur Fläche und Haarlinie.
BoxDecoration kartenDeko(
  BuildContext context, {
  Color? hauch,
  double radius = 16,
  Color? grund,
}) {
  final flaeche = grund ?? Theme.of(context).cardColor;
  return BoxDecoration(
    color: hauch == null ? flaeche : null,
    gradient: hauch == null
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.75],
            colors: [
              Color.alphaBlend(hauch.withValues(alpha: 0.12), flaeche),
              flaeche,
            ],
          ),
    borderRadius: BorderRadius.circular(radius),
    // **Eine Kante für alle.** Kein farbiger Rand, auch nicht bei „läuft
    // gerade" — dafür ist der Hauch da, und daneben sagen es Wort und Zeichen
    // im Inhalt deutlicher, als eine Linie es je könnte.
    border: Border.all(color: Theme.of(context).dividerColor),
  );
}

enum KartenStufe {
  /// Der Normalfall: die Kartenfläche.
  ruhig,

  /// Eine Stufe höher — für die Karte, die den Schirm anführt.
  gehoben,
}

class Karte extends StatelessWidget {
  const Karte({
    super.key,
    required this.child,
    this.hauch,
    this.stufe = KartenStufe.ruhig,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.onTap,
  });

  final Widget child;

  /// Der Farbschimmer aus der Ecke. `null` = keine Farbe.
  final Color? hauch;

  final KartenStufe stufe;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grund = switch (stufe) {
      KartenStufe.ruhig => Theme.of(context).cardColor,
      KartenStufe.gehoben => scheme.surfaceContainerHigh,
    };

    final inhalt = Container(
      padding: padding,
      decoration: kartenDeko(context,
          hauch: hauch, radius: radius, grund: grund),
      // **Ein durchsichtiges `Material` um den Inhalt.** Ohne das läuft jedes
      // `ListTile` in der Karte in eine Zusicherung: Es malt seinen Grund und
      // seine Tinte auf das nächste `Material`, und die Kartendekoration
      // deckte beides zu („background color or ink splashes may be
      // invisible"). Aufgefallen, als die erste Tippspiel-Zeile in eine Karte
      // gezogen wurde — die Karte selbst hatte das Problem schon immer, es
      // hatte nur noch niemand eine antippbare Zeile hineingelegt.
      child: Material(color: Colors.transparent, child: child),
    );

    if (onTap == null) return inhalt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: inhalt,
      ),
    );
  }
}
