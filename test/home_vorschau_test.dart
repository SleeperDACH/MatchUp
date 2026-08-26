import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/home_favorites.dart';
import 'package:matchup/app/home_tip_status.dart';
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
  home: const TeamRef(id: 'h', name: 'FC Bayern München', shortName: 'FCB'),
  away: const TeamRef(id: 'a', name: 'VfB Stuttgart', shortName: 'VfB'),
);

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: Startbildschirm — Richtung A', (tester) async {
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
      _liga(
        'l2',
        'BuLi 26/27',
        FantasyMode.liga,
        draft: DraftStatus.drafting,
      ),
      _liga('l3', 'DynastyTest', FantasyMode.dynasty),
      _liga('l4', 'testadmin', FantasyMode.liga),
    ];
    final runden = [
      _runde('r1', 'Xcode Xcode', ['bl1', 'bl2']),
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
          myFantasyLeaguesProvider.overrideWith((ref) async => ligen),
          myRoundsProvider.overrideWith((ref) async => runden),
          favoritenSpieleProvider.overrideWith((ref) async => [spiel]),
          // Das Spiel der Kopfkarte steht in **beiden** Runden: in der einen
          // getippt, in der anderen nicht. Genau der Fall, für den der Sockel
          // je Runde eine Zeile trägt — mit einer einzigen Runde sähe man ihm
          // nicht an, dass er mehrere kann.
          spielTippProvider.overrideWith(
            (ref, id) async => [
              SpielTipp(
                round: runden.first,
                tipp: MemberTip(
                  userId: 'ich',
                  fixtureId: id,
                  homeGoals: 2,
                  awayGoals: 0,
                ),
              ),
              SpielTipp(round: runden.last),
            ],
          ),
          fantasyManagersProvider.overrideWith((ref, id) async => const []),
          fantasyJoinRequestsProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          tipJoinRequestsProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          fantasyTipRoundProvider.overrideWith((ref, id) async => null),
          offeneTippsProvider.overrideWith(
            (ref, id) async => switch (id) {
              'r1' => OffeneTipps(anzahl: 18, frist: anstoss),
              'r2' => OffeneTipps(anzahl: 2, frist: anstoss),
              _ => OffeneTipps.leer,
            },
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

    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_vorschau.png'),
    );
  });
}
