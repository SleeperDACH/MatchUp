import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/home_favorites.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/auth/providers.dart';
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

TeamFixture _spiel(DateTime anstoss) => TeamFixture(
  id: 'sportmonks:1',
  kickoff: anstoss,
  status: FixtureStatus.scheduled,
  leagueName: 'Bundesliga',
  round: 3,
  // **Dortmund gegen HSV** ist mit Bedacht gewählt: Genau an dieser Paarung
  // fiel auf, dass die Kopfkarte ohne Vereinsfarbe dastand. Dortmunds Gelb ist
  // zu hell für die Grundfarbe und das Trikotweiß des HSV trägt keinen
  // Farbton — die beiden Fälle, an denen `vereinsTon` scheiterte. Wer hier
  // eine ruhigere Paarung einsetzt, verliert die Probe.
  home: const TeamRef(id: 'h', name: 'Borussia Dortmund', shortName: 'BVB'),
  away: const TeamRef(id: 'a', name: 'Hamburger SV', shortName: 'HSV'),
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

  testWidgets('Kartennamen werden nicht auf eine halbe Zeile gestaucht', (
    tester,
  ) async {
    // Der Fehler, den das hier festhält, meldete sich nirgends: Bei
    // zweizeiligem Sockel („Draft läuft" über „Pick 1") fehlten der Karte
    // rund fünf Punkte, und die nahm sich der `Flexible` um den Namen. Aus
    // „Tipptest" wurde auf dem Gerät lesbar „Tinntest" — formal passte alles,
    // es gab keinen Überlauf und keine Warnung.
    await _bauen(tester);

    // Eine volle Zeile bei 14 Punkt und `height: 1.2`.
    const zeile = 14 * 1.2;
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
  });
}

/// Baut den Homescreen mit gesetzten Zuständen auf.
Future<void> _bauen(WidgetTester tester) async {
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
  final spiel = _spiel(anstoss);

  final ligen = [
    _liga('l1', 'Draftest3', FantasyMode.liga),
    _liga('l2', 'BuLi 26/27', FantasyMode.liga, draft: DraftStatus.drafting),
    _liga('l3', 'Übungsliga', FantasyMode.dynasty),
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
        currentUserProvider.overrideWith((ref) => null),
        currentUsernameProvider.overrideWith((ref) async => 'SFV03'),
        unreadDmCountProvider.overrideWith((ref) => 18),
        myFantasyLeaguesProvider.overrideWith((ref) => Stream.value(ligen)),
        myRoundsProvider.overrideWith((ref) async => runden),
        favoritenSpieleProvider.overrideWith((ref) async => [spiel]),
        fantasyManagersProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        fantasyJoinRequestsProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        tipJoinRequestsProvider.overrideWith(
          (ref, id) => Stream.value(const []),
        ),
        newsProvider.overrideWith((ref, topic) async => const <NewsItem>[]),
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
