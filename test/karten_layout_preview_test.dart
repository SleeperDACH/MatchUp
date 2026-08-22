import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/matchup_chevron.dart';

import 'support/schrift.dart';

/// Vorschau zum **Vergleichen von Karten-Anordnungen** auf dem Homescreen.
///
/// Umgesetzt ist **D — Sockel** (`_KartenSockel` in `home_screen.dart`). Die
/// anderen drei bleiben als Vergleich stehen: sie zeigen, wogegen entschieden
/// wurde, und dienen als Ausgangspunkt, falls die Anordnung nochmal zur
/// Debatte steht. Wer eine Variante ändert, muss die Vorschau neu erzeugen:
/// `flutter test --update-goldens test/karten_layout_preview_test.dart`.
///
/// Kartenfläche, Verlauf, Rahmen, Radius und Maße bleiben in allen Varianten
/// identisch — verglichen wird nur, wie Logo, Name, Untertitel und
/// Zustandszeile darin angeordnet sind. Die Karten sind hier nachgebaut und
/// nicht die echten Widgets: die hängen an Riverpod-Providern (Manager,
/// Beitrittsanfragen, offene Tipps) und ließen sich ohne halben Homescreen
/// nicht rendern. Maße und Farben sind aus `home_screen.dart` übernommen.
const _cardHeight = 132.0;
const _tipCardHeight = 126.0;
const _rowPad = 12.0;
const _gap = 8.0;
const _screenWidth = 402.0; // iPhone 17 Pro in Punkten
const _tipGold = Color(0xFFFFC83D);

double get _cardWidth => (_screenWidth - 2 * _rowPad - 3 * _gap) / 4;

LinearGradient _verlauf(Color farbe, Color surface) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(farbe.withValues(alpha: 0.50), surface),
        Color.alphaBlend(farbe.withValues(alpha: 0.14), surface),
      ],
    );

/// Ein Datensatz für eine Karte — dieselben Beispiele wie auf dem Gerät.
class _Daten {
  const _Daten(this.name, this.unter, this.zustand, this.detail, this.farbe);
  final String name;
  final String unter;
  final String zustand;
  final String? detail;
  final Color farbe;
}

const _ligen = [
  _Daten('Draftest3', 'Redraft', 'Kader steht', null, MatchUpColors.green),
  _Daten('BuLi 26/27', 'Redraft', 'Offen', null, MatchUpColors.green),
  _Daten('DynastyTest', 'Dynasty', 'Offen', null, MatchUpColors.red),
  _Daten('testadmin', 'Redraft', 'Offen', null, MatchUpColors.green),
];

const _tipps = [
  _Daten('Xcode Xcode', 'Bundesliga +1', '18 Tipps offen', 'bis Fr., 18:30',
      _tipGold),
  _Daten('TEST TIPP', 'Bundesliga', '2 Tipps offen', 'bis Fr., 20:30', _tipGold),
];

/// Grundfläche einer Karte — in allen Varianten gleich.
Widget _flaeche(
        {required Color farbe, required double hoehe, required Widget kind}) =>
    SizedBox(
      width: _cardWidth,
      height: hoehe,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: _verlauf(farbe, MatchUpColors.base),
          border: Border.all(color: farbe.withValues(alpha: 0.65)),
        ),
        child: kind,
      ),
    );

Widget _marke(Color farbe, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: farbe, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: MatchUpChevron(size: size * 0.5, color: MatchUpColors.base),
    );

Widget _punkt(Color ton) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: ton, shape: BoxShape.circle),
    );

// ---------------------------------------------------------------------------
// A — wie es heute ist
// ---------------------------------------------------------------------------
Widget _variantA(_Daten d, double hoehe) => _flaeche(
      farbe: d.farbe,
      hoehe: hoehe,
      kind: Padding(
        padding: const EdgeInsets.fromLTRB(9, 9, 8, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [_marke(d.farbe, 26)]),
            const SizedBox(height: 7),
            Text(d.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.1)),
            Text(d.unter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Divider(
                height: 7,
                thickness: 1,
                color: d.farbe.withValues(alpha: 0.28)),
            Row(children: [
              _punkt(d.farbe),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.zustand,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (d.detail != null)
              Padding(
                padding: const EdgeInsets.only(left: 13, top: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.detail!,
                      maxLines: 1,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11)),
                ),
              ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// B — gleiche Anordnung, echte Staffelung: der Name führt, der Untertitel
//     tritt zurück (kleiner, leiser, gesperrt), damit nicht drei Zeilen
//     gleich laut sind.
// ---------------------------------------------------------------------------
Widget _variantB(_Daten d, double hoehe) => _flaeche(
      farbe: d.farbe,
      hoehe: hoehe,
      kind: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 9, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _marke(d.farbe, 26),
            const SizedBox(height: 8),
            // Flexibel, sonst drückt ein zweizeiliger Name die Karte auf.
            Flexible(
              child: Text(d.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, height: 1.05)),
            ),
            const SizedBox(height: 2),
            Text(d.unter.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const Spacer(),
            Row(children: [
              _punkt(d.farbe),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.zustand,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (d.detail != null)
              Padding(
                padding: const EdgeInsets.only(left: 13, top: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.detail!,
                      maxLines: 1,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10.5)),
                ),
              ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// C — Kopfzeile: Marke links, Untertitel rechts daneben. Die obere rechte
//     Ecke steht nicht mehr leer, und der Name bekommt den ganzen Mittelblock.
// ---------------------------------------------------------------------------
Widget _variantC(_Daten d, double hoehe) => _flaeche(
      farbe: d.farbe,
      hoehe: hoehe,
      kind: Padding(
        padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _marke(d.farbe, 22),
                const SizedBox(width: 5),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(d.unter.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Expanded(
              child: Text(d.name,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      height: 1.05)),
            ),
            Divider(
                height: 9,
                thickness: 1,
                color: d.farbe.withValues(alpha: 0.28)),
            Row(children: [
              _punkt(d.farbe),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.zustand,
                      maxLines: 1,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
              ),
            ]),
            if (d.detail != null)
              Padding(
                padding: const EdgeInsets.only(left: 13),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.detail!,
                      maxLines: 1,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10.5)),
                ),
              ),
          ],
        ),
      ),
    );

// ---------------------------------------------------------------------------
// D — der Zustand als Sockel: unten eine abgesetzte Leiste in der Kartenfarbe
//     statt einer Trennlinie. Oben Marke und Name, dazwischen Luft.
// ---------------------------------------------------------------------------
Widget _variantD(_Daten d, double hoehe) => _flaeche(
      farbe: d.farbe,
      hoehe: hoehe,
      kind: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 9, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _marke(d.farbe, 24),
                  const Spacer(),
                  Flexible(
                    child: Text(d.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            height: 1.05)),
                  ),
                  Text(d.unter,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: d.farbe.withValues(alpha: 0.20),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(15),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 5, 8, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    _punkt(d.farbe),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(d.zustand,
                            maxLines: 1,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ]),
                  if (d.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 13),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(d.detail!,
                            maxLines: 1,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 10)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

typedef _Bauer = Widget Function(_Daten, double);

Widget _panel(String titel, String hinweis, _Bauer bau) => SizedBox(
      width: _screenWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_rowPad, 10, _rowPad, 2),
            child: Text(titel,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_rowPad, 0, _rowPad, 8),
            child: Text(hinweis,
                style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.6))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _rowPad),
            child: Row(
              children: [
                for (var i = 0; i < _ligen.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  bau(_ligen[i], _cardHeight),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _rowPad),
            child: Row(
              children: [
                for (var i = 0; i < _tipps.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  bau(_tipps[i], _tipCardHeight),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Anordnung auf den Liga- und Tippspiel-Karten',
      (tester) async {
    tester.view.physicalSize = const Size(1720, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Das `Material` ist Pflicht, nicht Zierde: ohne es erbt jeder Text den
      // Fallback-Stil — rot, ohne Schriftfamilie. In der Vorschau kam das als
      // rote Kästchenreihe heraus und sah nach fehlender Schrift aus.
      home: Material(
        color: MatchUpColors.base,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _panel('A — heute', 'Marke oben, Name und Untertitel gleich laut',
                    _variantA),
                _panel('B — Staffelung',
                    'Name führt, Untertitel tritt als Versal-Zeile zurück', _variantB),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _panel('C — Kopfzeile',
                    'Marke links, Untertitel rechts daneben; Name bekommt den Block',
                    _variantC),
                _panel('D — Sockel',
                    'Zustand in abgesetzter Leiste statt hinter einer Linie',
                    _variantD),
              ],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/karten_layout_preview.png'));
  });
}
