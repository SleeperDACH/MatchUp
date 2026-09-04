import 'package:flutter/material.dart';

import '../theme.dart';
import '../typografie.dart';
import 'liquid_glass.dart';

/// Maße der schwebenden Navi-Kapsel.
///
/// Öffentlich, weil `extendBody: true` die Leiste über den Body legt: Screens,
/// deren Inhalt fest unten endet (Live-Tab), müssen den Platz selbst frei
/// halten und brauchen dafür dieselben Zahlen. Vorher standen sie doppelt im
/// Code — eine Änderung hier hätte den Abstand dort still verschoben.
const double navBarHeight = 58;

/// Mindestabstand der Kapsel zur Bildschirmunterkante. `SafeArea(minimum:)`
/// nimmt davon und dem Geräte-Sicherheitsbereich das **Maximum** — auf einem
/// Gerät mit Home-Indikator greift also dessen Wert, nicht dieser hier.
const double navBarBottomInset = 10;

/// Die schwebende Navi-Kapsel: Home · Live · Favoriten.
///
/// **Sie ist eine Kapsel, keine Leiste.** Über die volle Breite gezogen war sie
/// ein Balken mit drei weit auseinanderliegenden Zielen und großen Lücken
/// dazwischen — bei drei Zielen füllt nichts diese Breite. Jetzt ist sie nur so
/// breit wie ihr Inhalt und steht mittig: ein Bedienelement, das über dem
/// Inhalt schwebt, statt ihn unten abzuschneiden. Der Inhalt bekommt links und
/// rechts seine Fläche zurück.
///
/// **Das Glas verdunkelt, es hellt nicht auf.** Die Tönung war Weiß — über dem
/// schwarzen Grund ein Grauschleier, über einem hellen Nachrichtenbild grauer
/// Matsch, und genau dort verloren die gedämpften Ziele ihren Kontrast. Die
/// Leiste liegt über allem, was ein Tab gerade zeigt; sie kann sich nicht
/// darauf verlassen, dass der Untergrund dunkel ist. Verdunkeltes Glas hält ihn
/// unten, egal was er zeigt.
///
/// **Gewählt heißt hell** — dieselbe Marke wie jede andere Auswahl der App
/// (`PillChip`, `SegmentedTabBar`, der Wappenfilter): eine helle Fläche mit
/// hellerer Kante, Schrift in Snow. Vorher trug den Zustand allein die
/// Helligkeit von Symbol und Wort; über einem bunten Bild trennte das kaum. Ein
/// erster Versuch mit einer *dunklen* Mulde ging im dunklen Glas unter — Licht
/// wegzunehmen trägt nicht, wo ohnehin wenig ist.
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

  /// Innenrand der Kapsel um die Reihe der Ziele.
  static const _polster = EdgeInsets.symmetric(horizontal: 6, vertical: 5);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(20, 0, 20, navBarBottomInset),
      // **Zentriert über eine `Row`, nicht über `Align`.** Im
      // `bottomNavigationBar`-Platz misst das `Scaffold` mit lockeren
      // Constraints; ein `Align` ohne Höhenfaktor nähme sich davon das
      // Maximum und die Leiste wäre bildschirmhoch. Eine `Row` nimmt die
      // Breite und die Höhe ihres Kindes.
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LiquidGlass(
            borderRadius: 26,
            blur: 24,
            tintColor: Colors.black,
            tintOpacity: 0.58,
            borderOpacity: 0.14,
            child: Padding(
              padding: _polster,
              child: SizedBox(
                height: navBarHeight - _polster.vertical,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // **Die Ziele füllen die Höhe.** Ohne das ist die Tastfläche
                  // nur so hoch wie Symbol und Wort — gemessen 36,6 Punkte, das
                  // iOS-Mindestmaß sind 44. Ein `Row` zentriert seine Kinder in
                  // ihrer natürlichen Höhe; sichtbar ist der Unterschied nicht,
                  // fühlbar schon.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _ziele.length; i++)
                      _Ziel(
                        symbol: _ziele[i].$1,
                        symbolAktiv: _ziele[i].$2,
                        wort: _ziele[i].$3,
                        aktiv: i == index,
                        onTap: () => onSelected(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: MatchUpColors.snow.withValues(alpha: 0.06),
          highlightColor: MatchUpColors.snow.withValues(alpha: 0.04),
          // **Nur der Text wird ausgeschlossen, nicht der Knopf.** Lag das
          // `ExcludeSemantics` außen um den `InkWell`, verschwand mit dem
          // doppelten Wort auch dessen Tipp-Aktion: Die Vorlesehilfe kannte
          // dann drei Beschriftungen, die sich nicht bedienen ließen.
          child: ExcludeSemantics(
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
    );
  }
}
