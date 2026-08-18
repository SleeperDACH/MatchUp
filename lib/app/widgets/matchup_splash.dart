import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../features/auth/providers.dart';
import '../../features/fantasy/providers.dart';
import '../../features/tippspiel/providers.dart';
import '../theme.dart';
import 'matchup_chevron.dart';

/// „Der Homescreen hat sein Nötigstes geladen."
///
/// Bewusst nur **Ligen und Tipprunden**: sie bestimmen, ob der Schirm etwas
/// zu zeigen hat. News, Favoritenspiele und offene Tipps kommen nach und
/// füllen sich sichtbar auf — darauf zu warten hieße, den Startschirm an die
/// langsamste Quelle zu hängen.
///
/// Ohne Server oder ohne Anmeldung gibt es nichts zu laden; dann sofort wahr.
final homeBereitProvider = Provider<bool>((ref) {
  if (!AppConfig.isSupabaseConfigured) return true;
  if (ref.watch(currentUserProvider) == null) return true;
  return !ref.watch(myFantasyLeaguesProvider).isLoading &&
      !ref.watch(myRoundsProvider).isLoading;
});

/// Animierter Startbildschirm: die grüne Markenhälfte fährt von oben ein, die
/// rote von unten, beide treffen sich in der Mitte, dann erscheint die
/// Wortmarke. Danach **bleibt der Schirm stehen**, bis der Homescreen
/// geladen hat ([homeBereitProvider]) — er verdeckt also das Aufbauen statt
/// nach fester Zeit auf einen halb leeren Screen abzublenden.
///
/// Der Startschirm hängt damit an fremden Daten. Gegen einen ewig stehenden
/// Schirm (Netz weg, Abfrage hängt) gibt es [_maximaleWartezeit]; danach wird
/// abgeblendet, komme was wolle. Ein Tipp überspringt sofort.
///
/// Der **native** iOS-Startbildschirm lässt sich nicht animieren; er zeigt
/// nur noch den Hintergrund in derselben Farbe (`MatchUpColors.base`).
class MatchUpSplash extends ConsumerStatefulWidget {
  const MatchUpSplash({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MatchUpSplash> createState() => _MatchUpSplashState();
}

class _MatchUpSplashState extends ConsumerState<MatchUpSplash>
    with TickerProviderStateMixin {
  /// Notbremse, falls die Daten nie ankommen.
  static const _maximaleWartezeit = Duration(seconds: 8);

  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..forward();

  late final AnimationController _abblende = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  Timer? _notbremse;
  bool _zeigeKind = false;
  bool _weg = false;

  /// Anteile am Intro.
  static const _einfahrt = Interval(0.0, 0.62, curve: Curves.easeOutCubic);
  static const _aufprall = Interval(0.55, 0.78, curve: Curves.easeOut);
  static const _wortmarke = Interval(0.66, 1.0, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      // Erst jetzt die App aufbauen: Animation und Aufbau teilen sich den
      // Thread, und der Aufbau des Homescreens hält ihn spürbar an.
      setState(() => _zeigeKind = true);
      _pruefeFertig();
    });
    _abblende.addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() => _weg = true);
    });
    _notbremse = Timer(_maximaleWartezeit, _abblenden);
  }

  void _pruefeFertig() {
    if (!mounted || !_intro.isCompleted) return;
    if (ref.read(homeBereitProvider)) _abblenden();
  }

  void _abblenden() {
    _notbremse?.cancel();
    if (mounted && !_abblende.isAnimating && _abblende.isDismissed) {
      // Übersprungen, bevor das Intro durch war: die App muss trotzdem her.
      if (!_zeigeKind) setState(() => _zeigeKind = true);
      _abblende.forward();
    }
  }

  @override
  void dispose() {
    _notbremse?.cancel();
    _intro.dispose();
    _abblende.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sobald der Homescreen so weit ist, abblenden (auch wenn das Intro
    // schon fertig ist und nur noch gewartet wird).
    ref.listen<bool>(homeBereitProvider, (_, bereit) {
      if (bereit) _pruefeFertig();
    });

    return Stack(
      children: [
        if (_zeigeKind) widget.child,
        if (!_weg)
          AnimatedBuilder(
            animation: Listenable.merge([_intro, _abblende]),
            builder: (context, _) {
              final t = _intro.value;
              final weg = 1 - _einfahrt.transform(t); // 1 = draußen, 0 = mittig
              // Kurzer Stoß beim Zusammentreffen: hoch und wieder zurück.
              final stoss = _aufprall.transform(t);
              final puls =
                  1 + 0.07 * (stoss < 0.5 ? stoss * 2 : (1 - stoss) * 2);
              final wort = _wortmarke.transform(t);

              return Opacity(
                opacity: 1 - _abblende.value,
                child: GestureDetector(
                  // „Interaktiv": wer nicht warten will, tippt einmal.
                  onTap: _abblenden,
                  // Material, sonst zeichnet Flutter Text ohne Unterlage mit
                  // dem gelben Doppelstrich („missing Material widget").
                  child: Material(
                    color: MatchUpColors.base,
                    child: Center(
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
                          // Steht der Schirm und wartet auf die Daten, zeigt
                          // das Pulsieren, dass etwas passiert. Vorher wäre
                          // es nur Unruhe neben der Einfahrt.
                          SizedBox(
                            height: 34,
                            child: Opacity(
                              opacity: _intro.isCompleted ? 1 : 0,
                              child: const _Ladepunkte(),
                            ),
                          ),
                        ],
                      ),
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

/// Drei Punkte, die nacheinander aufleuchten — in den Markenfarben. Zeigt,
/// dass der Startschirm auf Daten wartet und nicht hängt.
class _Ladepunkte extends StatefulWidget {
  const _Ladepunkte();

  @override
  State<_Ladepunkte> createState() => _LadepunkteState();
}

class _LadepunkteState extends State<_Ladepunkte>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  static const _farben = [
    MatchUpColors.green,
    MatchUpColors.snow,
    MatchUpColors.red,
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 9),
              Opacity(
                // Versetzt: jeder Punkt hat sein eigenes Drittel der Runde.
                opacity: 0.25 + 0.75 * _staerke((_c.value + i / 3) % 1.0),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: _farben[i], shape: BoxShape.circle),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Kurzes Aufleuchten im ersten Drittel, danach dunkel.
  double _staerke(double t) {
    if (t > 0.5) return 0;
    final x = t * 2; // 0..1 im ersten Drittel
    return x < 0.5 ? x * 2 : (1 - x) * 2;
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
            child: ClipRect(clipper: const _Haelfte(links: true), child: marke),
          ),
          Transform.translate(
            offset: Offset(0, weg * strecke),
            child: ClipRect(clipper: const _Haelfte(links: false), child: marke),
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
