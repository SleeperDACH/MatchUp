import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/fantasy/ui/matchup_hero.dart';

import 'support/schrift.dart';
import 'package:matchup/core/ui/app_avatar.dart';

/// Vorschau des **MatchUp-Banners** in allen vier Zuständen.
///
/// `MatchupBanner` bekommt seine Daten explizit übergeben (der Provider-Teil
/// steckt in `MatchupHero`) — dadurch lässt sich der Schirm ohne einen
/// einzigen Provider zeigen. Auf dem Gerät sieht man immer nur den einen
/// Zustand, den die eigene Liga gerade hat.
void main() {
  setUpAll(() async {
    await ladeSchrift();
    // Der Anpfiff steht als „Fr., 20:30" da — ohne Gebietsdaten wirft der
    // Formatierer.
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: MatchUp-Banner', (tester) async {
    // **Hoch genug für alle Zustände.** Bei 1180 lagen die drei neuen Kästen
    // (Prognose, Prognose ohne Streuung, Vorher in Karussell-Höhe) unterhalb
    // des Bildrands — der Test lief grün, und zu sehen war ausgerechnet der
    // Fall nicht, für den der Kasten gebaut wurde.
    tester.view.physicalSize = const Size(402 * 3, 1900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Widget banner(String titel, Widget w) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titel,
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1)),
              const SizedBox(height: 4),
              w,
            ],
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ListView(
            children: [
              banner(
                'VOR DEM SPIELTAG',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  // Fester Anpfiff, kein `DateTime.now()`: Die Vorschau
                  // schreibt ihn unter das „VS", und ein gleitendes Datum
                  // machte das Bild von Tag zu Tag anders.
                  anpfiff: DateTime(2026, 9, 4, 20, 30),
                  onTap: () {},
                ),
              ),
              // **Derselbe Zeitpunkt, aber mit Grundlage.** Sobald es
              // gewertete Spieltage gibt, wird aus der Ankündigung ein
              // Vergleich: voraussichtliche Punkte beider Seiten und das Band
              // der Siegchance. Ohne dieses zweite Bild ließe sich nicht
              // beurteilen, was die Karte vor dem Spieltag eigentlich zeigt —
              // auf dem Gerät sieht man immer nur den einen Zustand, den die
              // eigene Liga gerade hat.
              banner(
                'VOR DEM SPIELTAG · MIT PROGNOSE',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  anpfiff: DateTime(2026, 9, 4, 20, 30),
                  homeProjektion: 212.4,
                  awayProjektion: 178.9,
                  siegchanceHeim: 0.63,
                  onTap: () {},
                ),
              ),
              // **Prognose ja, Siegchance nein.** Nach dem ersten gewerteten
              // Spieltag gibt es Schnitte, aber noch keine messbare Streuung —
              // dann steht der Vergleich da und das Band bleibt weg, statt
              // 50/50 zu behaupten.
              banner(
                'VOR DEM SPIELTAG · PROGNOSE OHNE STREUUNG',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  anpfiff: DateTime(2026, 9, 4, 20, 30),
                  homeProjektion: 212.4,
                  awayProjektion: 178.9,
                  onTap: () {},
                ),
              ),
              banner(
                'LIVE',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 48.4,
                  awayPoints: 51.2,
                  homeMe: true,
                  awayMe: false,
                  live: true,
                  started: true,
                  mine: true,
                  onTap: () {},
                ),
              ),
              banner(
                'BEENDET',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: 'lennartruepke',
                  homePoints: 92,
                  awayPoints: 78.5,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: true,
                  mine: true,
                  onTap: () {},
                ),
              ),
              // Der Fall, der auf dem Gerät den schwarz-gelben Balken zeigte:
              // Im MatchUp-Tab steckt der Kasten in einem PageView **fester**
              // Höhe. Hier steht er in genau derselben, mit demselben Rand und
              // den längsten Inhalten — wächst er wieder über sie hinaus,
              // wirft dieser Test statt des Simulators.
              banner(
                'IN KARUSSELL-HÖHE (${kMatchupBannerHoehe.toInt()} px)',
                SizedBox(
                  height: kMatchupBannerHoehe,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                    child: MatchupBanner(
                      round: 34,
                      homeName: 'lennartruepke',
                      awayName: 'Spitzenreiter04',
                      homePoints: 128.4,
                      awayPoints: 99.5,
                      homeMe: true,
                      awayMe: false,
                      live: true,
                      started: true,
                      mine: true,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
              // **Derselbe Wächter für den Vorher-Zustand.** Der Kasten oben
              // prüft die Karussell-Höhe nur mit angepfiffenem Spieltag — der
              // Zweig davor war damit ungedeckt, und genau dort ist jetzt eine
              // Zeile dazugekommen. Ein Überlauf hier hat schon einmal den
              // schwarz-gelben Balken aufs Gerät gebracht.
              banner(
                'VOR DEM SPIELTAG IN KARUSSELL-HÖHE '
                    '(${kMatchupBannerHoehe.toInt()} px)',
                SizedBox(
                  height: kMatchupBannerHoehe,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
                    child: MatchupBanner(
                      round: 34,
                      homeName: 'lennartruepke',
                      awayName: 'Spitzenreiter04',
                      homePoints: 0,
                      awayPoints: 0,
                      homeMe: true,
                      awayMe: false,
                      live: false,
                      started: false,
                      mine: true,
                      anpfiff: DateTime(2026, 9, 4, 20, 30),
                      homeProjektion: 1284.6,
                      awayProjektion: 999.5,
                      siegchanceHeim: 0.63,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
              banner(
                'SPIELFREI',
                MatchupBanner(
                  round: 3,
                  homeName: 'SFV03',
                  awayName: null,
                  homePoints: 0,
                  awayPoints: 0,
                  homeMe: true,
                  awayMe: false,
                  live: false,
                  started: false,
                  mine: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/matchup_banner_vorschau.png'),
    );

    // **Das Konto-Profilbild, kein Kreis mit Buchstaben.** Der Avatar wurde
    // hier selbst gezeichnet, obwohl die App mit `AppAvatar` längst einen
    // Baustein dafür hat — im Seitenmenü, im Ligaprofil und in der Teamliste
    // stand das echte Bild, ausgerechnet im Duell nicht.
    expect(find.byType(AppAvatar), findsWidgets,
        reason: 'die Banner zeigen Profilbilder');
  });
}
