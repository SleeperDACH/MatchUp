import 'package:flutter/material.dart';

import '../theme.dart';
import 'matchup_chevron.dart';

/// Animierter Startbildschirm: die grüne Hälfte der Marke fährt von oben ein,
/// die rote von unten, beide treffen sich in der Mitte. Danach erscheint die
/// Wortmarke, dann blendet der Schirm auf die App ab.
///
/// Liegt über [child], statt es zu ersetzen — der Aufbau der App beginnt aber
/// erst, wenn die Marke steht **und** die Wortmarke da ist. Grund: Animation
/// und Aufbau teilen sich denselben Thread, und der Aufbau des Homescreens
/// hält ihn spürbar an — im Debug-Build sekundenlang. Wo dieser Halt liegt,
/// kann man wählen; er gehört ans Ende, wenn nichts Auffälliges mehr passiert,
/// nicht mitten in die Einfahrt. Ein Tipp überspringt.
///
/// Der **native** iOS-Startbildschirm (LaunchScreen.storyboard) lässt sich
/// nicht animieren; er zeigt nur noch den Hintergrund in derselben Farbe
/// (`MatchUpColors.base`). Stünde dort weiter das fertige Logo, sähe man es
/// erst fertig, dann verschwinden und wieder einfliegen.
class MatchUpSplash extends StatefulWidget {
  const MatchUpSplash({super.key, required this.child});

  final Widget child;

  @override
  State<MatchUpSplash> createState() => _MatchUpSplashState();
}

class _MatchUpSplashState extends State<MatchUpSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  /// Die App wird erst gebaut, wenn die Marke steht (siehe Klassenkommentar).
  bool _zeigeKind = false;

  /// Anteile am Gesamtablauf.
  static const _einfahrt = Interval(0.0, 0.52, curve: Curves.easeOutCubic);
  static const _aufprall = Interval(0.46, 0.66, curve: Curves.easeOut);
  static const _wortmarke = Interval(0.55, 0.82, curve: Curves.easeOut);
  static const _abblende = Interval(0.86, 1.0, curve: Curves.easeIn);

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_zeigeKind && _c.value >= _wortmarke.end) {
        setState(() => _zeigeKind = true);
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_zeigeKind) widget.child,
        AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (_c.isCompleted) return const SizedBox.shrink();
            final t = _c.value;
            final weg = 1 - _einfahrt.transform(t); // 1 = draußen, 0 = mittig
            // Kurzer Stoß beim Zusammentreffen: hoch und wieder zurück.
            final stoss = _aufprall.transform(t);
            final puls = 1 + 0.07 * (stoss < 0.5 ? stoss * 2 : (1 - stoss) * 2);
            final wort = _wortmarke.transform(t);

            return Opacity(
              opacity: 1 - _abblende.transform(t),
              child: GestureDetector(
                // „Interaktiv": wer nicht warten will, tippt einmal.
                onTap: () => _c.animateTo(1.0,
                    duration: const Duration(milliseconds: 220)),
                child: Container(
                  color: MatchUpColors.base,
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: puls,
                        child: _GeteilteMarke(size: 108, weg: weg),
                      ),
                      SizedBox(height: 26 + 8 * (1 - wort)),
                      Opacity(
                        opacity: wort,
                        child: const _Wortmarke(fontSize: 40),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Die Marke in ihren beiden Hälften, jede um [weg] × Strecke verschoben:
/// grün nach oben, rot nach unten. Bei `weg == 0` steht das Logo.
class _GeteilteMarke extends StatelessWidget {
  const _GeteilteMarke({required this.size, required this.weg});

  final double size;

  /// 0 = zusammengesetzt, 1 = ganz auseinander.
  final double weg;

  @override
  Widget build(BuildContext context) {
    // Reichlich Weg, damit die Hälften wirklich von außerhalb kommen.
    final strecke = MediaQuery.sizeOf(context).height * 0.55;
    final breite = size * 58.0 / 54.4; // Seitenverhältnis des Chevrons
    final marke = MatchUpChevron(size: size);
    return SizedBox(
      width: breite,
      height: size,
      child: Stack(
        children: [
          Transform.translate(
            offset: Offset(0, -weg * strecke),
            child: ClipRect(
              clipper: const _Haelfte(links: true),
              child: marke,
            ),
          ),
          Transform.translate(
            offset: Offset(0, weg * strecke),
            child: ClipRect(
              clipper: const _Haelfte(links: false),
              child: marke,
            ),
          ),
        ],
      ),
    );
  }
}

/// Schneidet die linke bzw. rechte Hälfte frei. Die Marke ist genau in der
/// Mitte geteilt (grün links, rot rechts) — dieselbe Trennung wie im
/// Marken-SVG.
class _Haelfte extends CustomClipper<Rect> {
  const _Haelfte({required this.links});

  final bool links;

  @override
  Rect getClip(Size size) => links
      ? Rect.fromLTWH(0, 0, size.width / 2, size.height)
      : Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);

  @override
  bool shouldReclip(_Haelfte old) => old.links != links;
}

/// „MatchUp" wie im Logo — „Up" in Grün.
class _Wortmarke extends StatelessWidget {
  const _Wortmarke({required this.fontSize});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: MatchUpColors.snow,
          height: 1.0,
        ),
        children: const [
          TextSpan(text: 'Match'),
          TextSpan(text: 'Up', style: TextStyle(color: MatchUpColors.green)),
        ],
      ),
    );
  }
}
