import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../features/auth/providers.dart';
import '../../features/fantasy/providers.dart';
import '../../features/news/providers.dart';
import '../../features/tippspiel/providers.dart';
import '../home_favorites.dart';
import '../theme.dart';
import 'matchup_chevron.dart';

/// „Der Homescreen hat sein Nötigstes geladen."
///
/// Gewartet wird auf **alles, was den Schirm von oben nach unten füllt**:
/// die Kopfkarte mit dem nächsten Spiel des Favoriten
/// ([favoritenSpieleProvider]), Ligen und Tipprunden — und die News ganz
/// unten.
///
/// Vorher standen hier nur Ligen und Tipprunden, mit der Begründung, man
/// dürfe den Startschirm nicht an die langsamste Quelle hängen. Das Argument
/// stimmt technisch und war in der Sache trotzdem falsch: Der Schirm blendete
/// ab, und **dann** wuchsen Kopfkarte und Newsblock nach — der Screen sprang
/// unter dem Daumen. Gewünscht: *„Bitte verlänger den Ladescreen der App, bis
/// das Match über den Ligen geladen hat und die News da sind."*
///
/// `isLoading` ist bei einem **Fehler** falsch. Eine Quelle, die scheitert,
/// hält den Schirm also nicht fest — sie ist fertig, nur eben ohne Inhalt.
/// Gegen echtes Hängen steht die Notbremse in [MatchUpSplash].
///
/// Ganz nebenbei ist der Aufbau danach schneller: Die vier Abfragen laufen
/// schon während des Intros und liegen fertig im Cache, wenn der Homescreen
/// zum ersten Mal baut.
///
/// Ohne Server oder ohne Anmeldung gibt es nichts zu laden; dann sofort wahr.
final homeBereitProvider = Provider<bool>((ref) {
  if (!AppConfig.isSupabaseConfigured) return true;
  if (ref.watch(currentUserProvider) == null) return true;
  return !ref.watch(myFantasyLeaguesProvider).isLoading &&
      !ref.watch(myRoundsProvider).isLoading &&
      !ref.watch(favoritenSpieleProvider).isLoading &&
      !ref.watch(newsProvider(homeNewsThema)).isLoading;
});

/// Animierter Startbildschirm: die grüne Markenhälfte fährt von oben ein, die
/// rote von unten, beide treffen sich in der Mitte, dann erscheint die
/// Wortmarke. Danach **bleibt der Schirm stehen**, bis der Homescreen
/// vollständig geladen hat ([homeBereitProvider]) — er verdeckt also das
/// Aufbauen statt nach fester Zeit auf einen halb leeren Screen abzublenden,
/// der sich danach unter dem Daumen weiterfüllt.
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
  ///
  /// Seit die News mit dazugehören, hängt der Schirm an einem Abruf, der über
  /// eine Edge Function nach draußen geht — kalt dauert der auch mal ein paar
  /// Sekunden. Die Bremse muss deshalb länger sein als ein realistisch
  /// langsamer Abruf, sonst wird aus dem Notfall der Normalfall und die
  /// Verlängerung wirkungslos. Wem es zu lang ist, der tippt einmal.
  static const _maximaleWartezeit = Duration(seconds: 12);

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
      if (s == AnimationStatus.completed) _pruefeFertig();
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
    if (!mounted || _abblende.isAnimating || !_abblende.isDismissed) return;
    // Jetzt erst die App aufbauen. Vorher tat der Schirm das gleich nach dem
    // Intro — und der Aufbau des Homescreens blockiert den Thread so lange,
    // dass ausgerechnet die Ladeanzeige darüber einfror. Solange gewartet
    // wird, gehört der Thread der Animation.
    setState(() => _zeigeKind = true);
    // Erst nach dem (teuren) Aufbau-Frame abblenden, sonst ruckelt die
    // Überblendung genauso.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _abblende.forward();
    });
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

/// Wanderndes Ladezeichen in den Markenfarben: eine Welle läuft von **links
/// nach rechts**, der aktive Punkt streckt sich dabei zur Kapsel. Zeigt, dass
/// der Startschirm auf Daten wartet und nicht hängt.
class _Ladepunkte extends StatefulWidget {
  const _Ladepunkte();

  @override
  State<_Ladepunkte> createState() => _LadepunkteState();
}

class _LadepunkteState extends State<_Ladepunkte>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  static const _farben = [
    MatchUpColors.green,
    MatchUpColors.snow,
    MatchUpColors.red,
  ];

  /// Zeitlicher Versatz je Punkt. Kleiner als ein Drittel, damit die Welle
  /// zusammenhängt statt in drei Einzelblinker zu zerfallen.
  static const _versatz = 0.16;

  static const _hoehe = 7.0;
  static const _breiteRuhe = 7.0;
  static const _breiteAktiv = 17.0;

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
              if (i > 0) const SizedBox(width: 7),
              _punkt(i),
            ],
          ],
        );
      },
    );
  }

  Widget _punkt(int i) {
    // **Minus** der Versatz: der linke Punkt läuft voraus, die Welle wandert
    // nach rechts. Mit Plus lief sie andersherum.
    final phase = (_c.value - i * _versatz) % 1.0;
    final staerke = _welle(phase);
    return Container(
      width: _breiteRuhe + (_breiteAktiv - _breiteRuhe) * staerke,
      height: _hoehe,
      decoration: BoxDecoration(
        color: _farben[i].withValues(alpha: 0.28 + 0.72 * staerke),
        borderRadius: BorderRadius.circular(_hoehe / 2),
      ),
    );
  }

  /// Weicher Ausschlag in der ersten Hälfte der Runde, danach Ruhe — ohne
  /// Knick am Anfang und Ende, sonst zuckt die Welle.
  double _welle(double t) => t < 0.5 ? math.sin(t * 2 * math.pi) : 0;
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
