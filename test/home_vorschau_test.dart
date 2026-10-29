import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/typografie.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/home_favorites.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/friends/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/leagues/providers.dart';
import 'package:matchup/features/messaging/providers.dart';
import 'package:matchup/features/news/models/news_item.dart';
import 'package:matchup/features/news/providers.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';
import 'package:matchup/features/tippspiel/providers.dart';

import 'support/schrift.dart';

/// Vorschau des **ganzen Startbildschirms** — kein Regressionstest:
///   flutter test --update-goldens test/home_vorschau_test.dart
///   -> test/goldens/home_vorschau.png
///
/// Bis hierher ließ sich der Homescreen nur im Simulator ansehen, und das
/// heißt: nur in den Zuständen, die der eigene Testaccount gerade hat. Genau
/// daran scheiterte die Abnahme von „Richtung A": Der Account hatte keine
/// eigenständige Tipprunde, also war der ganze neue Zeilen-Abschnitt auf dem
/// Gerät nicht zu sehen — und ein zweiter Screenshot hätte daran nichts
/// geändert.
///
/// Hier stehen die Zustände deshalb im Test: eine Kopfkarte mit noch offenem
/// Tipp, vier Ligen (darunter ein laufender Draft, der als einziger den
/// Rahmen färbt), zwei Tipprunden als Zeilen. Verglichen wird die
/// **Anordnung**, nicht das Bild — zwei Sorten Grafik fehlen im Test
/// systembedingt: Wappen und Wettbewerbslogos laden kein Netz (dort stehen
/// die Ersatzflächen), und Material-Symbole werden zu leeren Kästchen, weil
/// nur die App-Schrift in den Test geladen wird. Beides ist kein Befund.
///
/// `AppConfig.supabaseInitialized` muss an: ohne das Flag hält der Screen
/// sich für serverlos und zeigt statt allem eine Hinweiskarte.
/// **Der Bildvergleich läuft nur mit `--update-goldens`.** Das Bild zeigt den
/// heutigen Tag ("Donnerstag, 27. Aug."), weil beide Schirme intern
/// `DateTime.now()` benutzen — der Live-Tab wählt beim Öffnen heute, die
/// Kopfkarte schreibt das Datum ihres Spiels hin. Ein fest eingecheckter
/// Vergleich wäre damit **jeden Tag rot**, und ein Test, der täglich rot ist,
/// bringt niemandem etwas außer der Gewohnheit, ihn zu übergehen. Die Vorschau
/// ist zum Ansehen da; was wirklich gehalten werden muss, steht als Messung
/// daneben.

FantasyLeague _liga(
  String id,
  String name,
  FantasyMode mode, {
  DraftStatus draft = DraftStatus.setup,
  String? farbe,
}) => FantasyLeague(
  id: id,
  name: name,
  mode: mode,
  season: 2026,
  pickTime: DraftPickTime.h2,
  scoring: const FantasyScoringRules(),
  roster: RosterConfig.standard,
  inviteCode: 'ABC123',
  draftStatus: draft,
  createdBy: 'ich',
  logoColor: farbe,
);

TipRound _runde(String id, String name, List<String> ligen) => TipRound(
  id: id,
  name: name,
  leagueId: ligen.first,
  leagueIds: ligen,
  season: 2026,
  inviteCode: 'XYZ789',
  scoring: const ScoringRules(),
  createdBy: 'ich',
);

TeamFixture _spiel(
  DateTime anstoss, {
  String id = 'sportmonks:1',
  String heim = 'Borussia Dortmund',
  String heimKurz = 'BVB',
  String gast = 'Hamburger SV',
  String gastKurz = 'HSV',
  int? tore,
}) => TeamFixture(
  id: id,
  kickoff: anstoss,
  status: tore == null ? FixtureStatus.scheduled : FixtureStatus.finished,
  homeScore: tore,
  awayScore: tore == null ? null : 1,
  leagueName: 'Bundesliga',
  round: 3,
  // **Dortmund gegen HSV** ist mit Bedacht gewählt: Genau an dieser Paarung
  // fiel auf, dass die Kopfkarte ohne Vereinsfarbe dastand. Dortmunds Gelb ist
  // zu hell für die Grundfarbe und das Trikotweiß des HSV trägt keinen
  // Farbton — die beiden Fälle, an denen `vereinsTon` scheiterte. Wer hier
  // eine ruhigere Paarung einsetzt, verliert die Probe.
  home: TeamRef(id: 'h$id', name: heim, shortName: heimKurz),
  away: TeamRef(id: 'a$id', name: gast, shortName: gastKurz),
);

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: Startbildschirm — Richtung A', (tester) async {
    await _bauen(tester);
    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_vorschau.png'),
    );
  });

  testWidgets('Ohne Favoriten steht oben die Vereinswahl', (tester) async {
    await _bauen(tester, ohneFavoriten: true);
    expect(find.text('Wähle deinen Verein'), findsOneWidget);
    expect(find.bySemanticsLabel('Hamburger SV als Favorit wählen'),
        findsOneWidget);
    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_ohne_favoriten.png'),
    );
  });

  testWidgets('Mit Favoriten keine Vereinswahl', (tester) async {
    await _bauen(tester);
    expect(find.text('Wähle deinen Verein'), findsNothing);
  });

  testWidgets('Kartennamen werden nicht auf eine halbe Zeile gestaucht', (
    tester,
  ) async {
    // Der Fehler, den das hier festhält, meldete sich nirgends: Bei
    // zweizeiligem Sockel („Draft läuft" über „Pick 1") fehlten der Karte
    // rund fünf Punkte, und die nahm sich der `Flexible` um den Namen. Aus
    // „Tipptest" wurde auf dem Gerät lesbar „Tinntest" — formal passte alles,
    // es gab keinen Überlauf und keine Warnung.
    await _bauen(tester);

    // Eine volle Zeile bei der Kartenschrift (`Schrift.text`) und
    // `height: 1.2`.
    const zeile = Schrift.text * 1.2;
    for (final name in ['Tipptest', 'TEST TIPP', 'BuLi 26/27', 'Draftest3']) {
      final box = tester.renderObject<RenderBox>(find.text(name));
      expect(
        box.size.height,
        greaterThanOrEqualTo(zeile),
        reason:
            '„$name" bekommt nur ${box.size.height} statt $zeile Punkt — '
            'die Karte ist zu kurz, und der Name wird beschnitten',
      );
    }

    // **Nie mitten im Wort.** „Übungsliga" brach zweimal, jedes Mal nach
    // einer Schriftänderung (Inter, dann die Vier-Stufen-Leiter). Ein Wort
    // steht auf **einer** Zeile — höher als anderthalb Zeilen darf es nicht
    // sein.
    final wort = tester.renderObject<RenderBox>(find.text('Übungsliga'));
    expect(wort.size.height, lessThan(zeile * 1.5),
        reason: '„Übungsliga" bricht mitten im Wort um');
  });
}

/// Baut den Homescreen mit gesetzten Zuständen auf.
Future<void> _bauen(WidgetTester tester, {bool ohneFavoriten = false}) async {
  final vorher = AppConfig.supabaseInitialized;
  AppConfig.supabaseInitialized = true;
  addTearDown(() => AppConfig.supabaseInitialized = vorher);

  // Die echte Gerätefläche, nicht die 800×600 des Testfensters — und zwar
  // über `tester.view`, **nicht** über `setSurfaceSize`. Letzteres ändert
  // nur, worauf gezeichnet wird; die `MediaQuery` blieb bei 800×600. Das
  // fällt fast nirgends auf, aber `_Bleed` und `leagueCardWidth` rechnen
  // ihre Maße genau daraus: Die Kartenreihe stand 800 breit hinter einem
  // 402 breiten Bild, jede Karte doppelt so breit wie auf dem Gerät, und
  // die erste hing links außerhalb. Ein `MediaQuery`-Widget um den Screen
  // reicht ebenso wenig — die Größe muss aus der View kommen, sonst
  // widersprechen sich Bild und Maße weiter.
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // Ein fester Anstoß am selben Tag: so trägt die Kopfkarte ihre
  // „HEUTE"-Marke, ohne dass die Vorschau von der Uhr abhängt.
  final heute = DateTime.now();
  final anstoss = DateTime(heute.year, heute.month, heute.day, 20, 30);
  // **„Mein Wochenende" braucht mehr als eine Partie.** Die Kopfkarte nimmt
  // sich die erste; ohne weitere fiele der ganze Abschnitt weg, und genau der
  // soll hier zu sehen sein — mit einem gespielten Freitagsspiel, damit auch
  // das Ergebnis in der Zeile im Bild steht.
  final spiele = [
    _spiel(anstoss),
    _spiel(
      anstoss.subtract(const Duration(days: 3)),
      id: 'sportmonks:2',
      heim: 'FC Bayern München',
      heimKurz: 'FCB',
      gast: 'RB Leipzig',
      gastKurz: 'RBL',
      tore: 3,
    ),
    _spiel(
      anstoss.subtract(const Duration(days: 2, hours: 5)),
      id: 'sportmonks:3',
      heim: 'SC Freiburg',
      heimKurz: 'SCF',
      gast: 'Werder Bremen',
      gastKurz: 'SVW',
      tore: 1,
    ),
  ];

  final ligen = [
    _liga('l1', 'Draftest3', FantasyMode.liga),
    _liga('l2', 'BuLi 26/27', FantasyMode.liga, draft: DraftStatus.drafting),
    _liga('l3', 'Übungsliga', FantasyMode.liga),
    _liga('l4', 'testadmin', FantasyMode.liga),
  ];
  final runden = [
    _runde('r1', 'Tipptest', ['bl1', 'bl2']),
    _runde('r2', 'TEST TIPP', ['bl1']),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Angemeldet, aber ohne echten Supabase-User: den Screen
        // interessiert nur, ob überhaupt einer da ist — und die Karten
        // vergleichen die ID mit `createdBy`.
        currentUserProvider.overrideWith(
          (ref) => ohneFavoriten
              ? User(
                  id: 'ich',
                  appMetadata: const {},
                  userMetadata: const {},
                  aud: 'authenticated',
                  createdAt: DateTime(2026).toIso8601String(),
                )
              : null,
        ),
        // Mit Nutzer erscheint oben links das Profilbild; Profil und
        // Anfragen gingen sonst an `Supabase.instance`.
        currentProfileProvider.overrideWith((ref) async => null),
        incomingRequestsProvider.overrideWith((ref) => const []),
        // Geladen und leer — der Fall, für den die Favoriten-Leiste da ist.
        if (ohneFavoriten)
          favoritesProvider
              .overrideWith((ref) => FavoritesNotifier(null)..geladen = true),
        if (ohneFavoriten)
          leagueTeamsProvider.overrideWith((ref, id) => AsyncValue.data([
                for (final (i, n) in const [
                  'FC Bayern München',
                  'Borussia Dortmund',
                  'Hamburger SV',
                  'FC Schalke 04',
                  'Borussia Mönchengladbach',
                  'SC Freiburg',
                  'VfB Stuttgart',
                ].indexed)
                  TeamRef(id: 't$i', name: n, shortName: n.substring(0, 3)),
              ])),
        currentUsernameProvider.overrideWith((ref) async => 'SFV03'),
        unreadDmCountProvider.overrideWith((ref) => 18),
        myFantasyLeaguesProvider.overrideWith((ref) => Stream.value(ligen)),
        myRoundsProvider.overrideWith((ref) async => runden),
        // Die Tippliga, noch nicht beigetreten — der Zustand mit „Mitspielen".
        tippligaProvider.overrideWith((ref) async => const Tippliga(
            id: 'tippliga', name: 'Globales Tippspiel', mitglied: false,
            mitspieler: 27)),
        favoritenSpieleProvider
            .overrideWith((ref) async => ohneFavoriten ? const [] : spiele),
        fantasyManagersProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        fantasyJoinRequestsProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        tipJoinRequestsProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        // **Mit Meldungen im Bild.** Der News-Abschnitt ist seit dem Umbau
        // (untereinander statt quer, Bild über die volle Breite) der längste
        // Block des Schirms — mit leerer Liste sah man von ihm gar nichts.
        // Die Bilder selbst erscheinen in Vorschauen nicht (Dekodieren ist
        // echtes I/O); zu sehen ist die Ersatzfläche und die Anordnung.
        newsProvider.overrideWith((ref, topic) async => [
              NewsItem(
                title: 'Karetsas, Banzuzi und Co. — wer wird der '
                    '„neue Diomande"?',
                url: 'https://example.org/1',
                source: 'Sportschau',
                publishedAt: DateTime(2026, 9, 3, 9, 26),
                imageUrl: 'https://example.org/1.jpg',
              ),
              NewsItem(
                title: 'Atubolu spricht über Wechsel-Posse: '
                    '„Keine einfache Zeit"',
                url: 'https://example.org/2',
                source: 'Sportschau',
                publishedAt: DateTime(2026, 9, 3, 8, 10),
                imageUrl: 'https://example.org/2.jpg',
              ),
            ]),
      ],
      child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()),
    ),
  );
  // Die Provider lösen sich gestaffelt auf, und die Einblend-Animation
  // (`_Appear`) läuft dazu. `pumpAndSettle` würde an der pulsierenden
  // Draft-Anzeige hängen bleiben, die nie zur Ruhe kommt.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
