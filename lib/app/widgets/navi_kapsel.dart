import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';
import '../typografie.dart';

/// Maße der schwebenden Navi-Kapsel.
///
/// Öffentlich, weil `extendBody: true` die Leiste über den Body legt: Screens,
/// deren Inhalt fest unten endet (Live-Tab), müssen den Platz selbst frei
/// halten und brauchen dafür dieselben Zahlen. Vorher standen sie doppelt im
/// Code — eine Änderung hier hätte den Abstand dort still verschoben.
const double navBarHeight = 58;

/// Fußraum unter der Zielreihe. Maßgeblich ist das **Maximum** aus diesem Wert
/// und dem Geräte-Sicherheitsbereich — auf einem Gerät mit Home-Indikator
/// greift also dessen Wert, auf einem ohne dieser hier. Ohne den Fußraum
/// klebten die Wörter auf einem Telefon ohne Indikator an der Unterkante.
const double navBarBottomInset = 10;

/// Die untere Navileiste: Home · Live · Favoriten.
///
/// **Sie läuft von Kante zu Kante durch** (auf Ansage, 04.09.2026). Zwei
/// Zwischenstände liegen dahinter, und beide sind verworfen: eine Leiste mit
/// 20 Punkt Luft an den Seiten (dann sind es zwei Ränder, an denen der Inhalt
/// vorbeischaut) und eine Kapsel, die auf die Breite ihrer drei Ziele
/// schrumpfte. Die Kapsel löste zwar die großen Lücken zwischen den Zielen —
/// aber sie stand als Insel im Bild, und der Boden des Schirms hatte keinen
/// Abschluss mehr. Eine Leiste, die unten abschließt, muss unten abschließen.
///
/// **Das Glas verdunkelt, es hellt nicht auf.** Die Tönung war Weiß — über dem
/// schwarzen Grund ein Grauschleier, über einem hellen Nachrichtenbild grauer
/// Matsch, und genau dort verloren die ruhenden Ziele ihren Kontrast. Die
/// Leiste liegt über allem, was ein Tab gerade zeigt (`extendBody`); sie kann
/// sich nicht darauf verlassen, dass der Untergrund dunkel ist. Verdunkeltes
/// Glas hält ihn unten, egal was er zeigt.
///
/// **Sie benutzt bewusst nicht `LiquidGlass`.** Der Baustein bringt runde
/// Ecken, einen Schlagschatten und eine Kante auf **allen vier** Seiten mit —
/// alles drei richtig für eine schwebende Fläche und alles drei falsch für
/// eine Leiste am Bildschirmrand: Die runden Ecken ließen an den Außenkanten
/// Zwickel offen, der Schatten fiele ins Nichts, und von der Kante ist nur die
/// **obere** je zu sehen. `LiquidGlass` bleibt für die schwebenden Flächen
/// (Anmeldeschirm).
///
/// **Gewählt heißt hell** — dieselbe Marke wie jede andere Auswahl der App
/// (`PillChip`, `SegmentedTabBar`, der Wappenfilter): eine helle Fläche mit
/// hellerer Kante, Schrift in Snow. Vorher trug den Zustand allein die
/// Helligkeit von Symbol und Wort; über einem bunten Bild trennte das kaum.
///
/// **Kein Grün.** Die gefüllte grüne Pille war einmal das lauteste Element im
/// Bild; Grün heißt in dieser App „hier läuft etwas", und der Reiter, auf dem
/// man steht, läuft nicht.
class NaviKapsel extends StatelessWidget {
  const NaviKapsel({super.key, required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _ziele = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home, 'Home'),
    (Icons.sports_soccer_outlined, Icons.sports_soccer, 'Live'),
    (Icons.star_border, Icons.star, 'Favoriten'),
  ];

  @override
  Widget build(BuildContext context) {
    // Der Fußraum gehört **in** die Leiste, nicht darunter: Sonst liefe der
    // Inhalt des Tabs unter dem Home-Indikator durch, und die Leiste hörte
    // einen Zentimeter über der Unterkante auf.
    final fuss = math.max(
      MediaQuery.viewPaddingOf(context).bottom,
      navBarBottomInset,
    );

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            // Nur oben eine Kante — die drei anderen Seiten liegen am
            // Bildschirmrand. Es ist dieselbe Haarlinie, die in dieser App
            // jede Karte von ihrem Grund trennt.
            border: Border(
              top: BorderSide(
                color: MatchUpColors.snow.withValues(alpha: 0.10),
                width: 0.8,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: fuss),
            child: SizedBox(
              height: navBarHeight,
              child: Row(
                // **Die Ziele füllen die Höhe.** Ohne das ist die Tastfläche
                // nur so hoch wie Symbol und Wort — gemessen 36,6 Punkte, das
                // iOS-Mindestmaß sind 44. Ein `Row` zentriert seine Kinder in
                // ihrer natürlichen Höhe; sichtbar ist der Unterschied nicht,
                // fühlbar schon.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _ziele.length; i++)
                    Expanded(
                      child: _Ziel(
                        symbol: _ziele[i].$1,
                        symbolAktiv: _ziele[i].$2,
                        wort: _ziele[i].$3,
                        aktiv: i == index,
                        onTap: () => onSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ein Ziel in der Kapsel: Symbol über Wort, aktiv in der hellen Marke.
class _Ziel extends StatelessWidget {
  const _Ziel({
    required this.symbol,
    required this.symbolAktiv,
    required this.wort,
    required this.aktiv,
    required this.onTap,
  });

  final IconData symbol;
  final IconData symbolAktiv;
  final String wort;
  final bool aktiv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // **Die Ruhenden dürfen lesbar sein.** Sie standen auf 0,45, weil der
    // aktive Zustand allein aus dem Helligkeitsunterschied kam — je heller
    // die Ruhenden, desto schwächer das Signal. Seit die helle Marke den
    // aktiven Reiter trägt, muss die Helligkeit das nicht mehr leisten, und
    // „Live" und „Favoriten" müssen nicht länger fast verschwinden, damit man
    // „Home" findet.
    final farbe = aktiv
        ? MatchUpColors.snow
        : MatchUpColors.snow.withValues(alpha: 0.62);

    return Semantics(
      button: true,
      selected: aktiv,
      label: wort,
      child: Material(
        type: MaterialType.transparency,
        // **Die ganze Spalte nimmt den Tipp an, nicht nur die Marke.** Die
        // Marke ist rund 90 Punkte breit, die Spalte ein Drittel des Schirms
        // — läge der Knopf nur unter der Marke, wären links und rechts davon
        // gut zwanzig Punkte tot, und ein Tipp knapp daneben täte nichts.
        child: InkWell(
          onTap: onTap,
          splashColor: MatchUpColors.snow.withValues(alpha: 0.05),
          highlightColor: MatchUpColors.snow.withValues(alpha: 0.03),
          // **Nur der Text wird ausgeschlossen, nicht der Knopf.** Lag das
          // `ExcludeSemantics` außen um den `InkWell`, verschwand mit dem
          // doppelten Wort auch dessen Tipp-Aktion: Die Vorlesehilfe kannte
          // dann drei Beschriftungen, die sich nicht bedienen ließen.
          child: ExcludeSemantics(
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                // **Die Tastfläche ist die Marke, nicht nur die Schrift.** 44
                // Punkte sind auf iOS das Mindestmaß; bei drei Zielen ist Platz
                // genug, ihn zu geben.
                constraints: const BoxConstraints(minWidth: 76),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: aktiv
                      ? MatchUpColors.snow.withValues(alpha: 0.13)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: aktiv
                        ? MatchUpColors.snow.withValues(alpha: 0.22)
                        : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(aktiv ? symbolAktiv : symbol, size: 22, color: farbe),
                    const SizedBox(height: 2),
                    Text(
                      wort,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: Schrift.winzig,
                        fontWeight: aktiv ? FontWeight.w800 : FontWeight.w500,
                        letterSpacing: 0.1,
                        height: 1.1,
                        color: farbe,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
