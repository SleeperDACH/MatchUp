import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_league_screen.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Liga-Übersicht** (erster Reiter).
///
/// Für diesen Schirm gab es lange keine — er hängt an einem Dutzend Provider,
/// und die Diagnose stand auf einem Gerätebild. Genau deshalb ist er auch nie
/// nachgebessert worden: Wer ihn ändert, sieht ihn sonst nur, wenn die eigene
/// Liga zufällig im richtigen Zustand ist.
///
/// Gezeigt wird die **laufende Saison** — der Zustand, in dem die beiden
/// Zeilengruppen „Mein Team" und „Liga" vollständig dastehen.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1999, 1, 1),
      nationality: 'DE',
    );

/// Ein Spiel mit frei wählbarer Runde — der zweite Vorschaufall braucht
/// mehrere Spieltage, der erste kommt mit einem aus.
Fixture spielMit(String h, String a, DateTime k, int runde, FixtureStatus st,
        [int? hs, int? as_]) =>
    Fixture(
      id: 'sportmonks:${h.hashCode}-$runde',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: 'Spieltag $runde',
      kickoff: k,
      home: TeamRef(id: h, name: h, shortName: h),
      away: TeamRef(id: a, name: a, shortName: a),
      status: st,
      homeScore: hs,
      awayScore: as_,
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    // Der Spieltags-Block formatiert Datumsangaben auf Deutsch.
    await initializeDateFormatting('de_DE');
  });

  setUp(() {
    // Der Ungelesen-Hinweis am Liga-Chat holt seine Lesemarke von dort;
    // ohne Mock wirft der Plugin-Kanal im Test.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Vorschau: Liga-Übersicht', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 950 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 4,
      tipEnabled: true,
    );

    final pool = [
      _p('a1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
      _p('a2', 'Nico Schlotterbeck', PlayerPosition.def, 'Borussia Dortmund'),
      _p('a3', 'Florian Wirtz', PlayerPosition.mid, 'RB Leipzig'),
      _p('a4', 'Randal Kolo Muani', PlayerPosition.fwd, 'Eintracht Frankfurt'),
    ];

    Fixture spiel(String h, String a, DateTime k, FixtureStatus st,
            [int? hs, int? as_]) =>
        Fixture(
          id: 'sportmonks:${h.hashCode}',
          leagueId: 'bundesliga',
          season: 2026,
          round: 3,
          roundName: 'Spieltag 3',
          kickoff: k,
          home: TeamRef(id: h, name: h, shortName: h),
          away: TeamRef(id: a, name: a, shortName: a),
          status: st,
          homeScore: hs,
          awayScore: as_,
        );
    final spiele = [
      spiel('FC Bayern München', 'VfB Stuttgart', DateTime(2026, 9, 12, 20, 30),
          FixtureStatus.finished, 2, 1),
      spiel('Borussia Dortmund', 'RB Leipzig', DateTime(2026, 9, 13, 15, 30),
          FixtureStatus.live, 1, 1),
      spiel('Eintracht Frankfurt', 'SC Freiburg',
          DateTime(2026, 9, 13, 15, 30), FixtureStatus.scheduled),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
          fantasyCurrentRoundProvider.overrideWith((ref) async => 3),
          fantasyManagersProvider.overrideWith(
            (ref, id) => Stream.value(const [
              FantasyManager(userId: 'ich', username: 'SFV03', draftPosition: 1),
              FantasyManager(
                  userId: 'gegner',
                  username: 'lennartruepke',
                  draftPosition: 2),
            ]),
          ),
          leagueTradesProvider.overrideWith((ref, id) => Stream.value(const [])),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          // Zwei Wechsel, damit die Transfers-Zeile ihren Hinweis zeigt — mit
          // leerer Liste stünde dort nur das Wort, und genau das war der
          // Vorwurf an die Zeilen vor der Überarbeitung.
          rosterMovesProvider.overrideWith((ref, id) => Stream.value([
                RosterMove(
                    id: 2,
                    leagueId: 'l1',
                    managerId: 'gegner',
                    playerId: 'a3',
                    zugang: true,
                    weg: 'fa',
                    passiertAm: DateTime(2026, 9, 12, 18)),
                RosterMove(
                    id: 1,
                    leagueId: 'l1',
                    managerId: 'gegner',
                    playerId: 'a4',
                    zugang: false,
                    passiertAm: DateTime(2026, 9, 12, 17, 59)),
              ])),
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              for (final p in pool)
                RosterEntry(
                    managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
            ]),
          ),
          leagueLineupsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          roundStatsProvider.overrideWith((ref, round) async => const {}),
          fantasySeasonFixturesProvider
              .overrideWith((ref) async => spiele),
          fantasyTipRoundProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FantasyLeagueScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // **Was gehalten werden muss, steht als Messung — vor dem Wächter.** Die
    // Zeilengruppen und der Spieltagsblock sind der Inhalt dieses Schirms;
    // ob der Duell-Kasten „VS" oder einen Punktestand zeigt, hängt am
    // Kalender und nicht am Code.
    expect(find.text('Aufstellung'), findsOneWidget);
    expect(find.text('Free Agency'), findsOneWidget);
    expect(find.text('Liga-Chat'), findsOneWidget);
    expect(find.text('3. SPIELTAG'), findsOneWidget);

    // **Und zwar genau einmal.** Jeder Zeitblock trug den Wettbewerb samt
    // Spieltag hinter dem Datum — bei sieben Anstoßzeiten siebenmal dieselbe
    // Auskunft, die eine Zeile höher schon als Abschnittsmarke steht.
    // Gemeldet als: „Das ist völlig unnötig, können wir wegmachen."
    expect(find.textContaining('Bundesliga, 3. Spieltag'), findsNothing);

    // **Der Bildvergleich läuft nur mit `--update-goldens`.** Die Fixtures
    // dieser Vorschau tragen feste Daten (12./13. September); ihr **Zustand**
    // rechnet der Schirm gegen `DateTime.now()`. Am 08.09. stand im
    // Duell-Kasten „VS · Anpfiff Sa., 20:30", am 13.09. ein laufendes 0:0 —
    // dieselbe Eingabe, ein anderes Bild, ohne dass jemand Code angefasst
    // hätte. Ein Test, der von selbst rot wird, ist einer, den man sich
    // abgewöhnt zu lesen; dieselbe Entscheidung wie bei Home und Live.
    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(FantasyLeagueScreen),
      matchesGoldenFile('goldens/liga_uebersicht_vorschau.png'),
    );
  });

  testWidgets('Vorschau: Liga-Übersicht vor dem Spieltag, mit Prognose',
      (tester) async {
    // **Der Zustand, den die Vorschau oben nicht zeigen kann.** Dort liegen
    // die Anstoßzeiten in der Vergangenheit, der Spieltag läuft also, und der
    // Duell-Kasten trägt den echten Punktestand — die Prognose wird dann
    // absichtlich unterdrückt.
    //
    // Damit war die neue Anzeige auf **dieser** Karte durch nichts gedeckt:
    // Ein grüner Lauf und ein unverändertes Bild belegen nur, dass nichts
    // kaputt ist. Dieselbe Lücke wie beim Banner-Wächter, der die
    // Karussell-Höhe lange nur mit angepfiffenem Spieltag prüfte.
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 950 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC123',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 4,
      tipEnabled: true,
    );

    // Zwei Manager mit je elf Spielern — die Prognose summiert die Schnitte
    // der **Startelf**, mit vier Spielern käme eine Zahl heraus, die nichts
    // über eine Elf sagt.
    final meine = [
      for (var i = 0; i < 11; i++)
        _p('m$i', 'Meiner $i', PlayerPosition.values[i % 4],
            'Borussia Dortmund'),
    ];
    final seine = [
      for (var i = 0; i < 11; i++)
        _p('g$i', 'Seiner $i', PlayerPosition.values[i % 4],
            'FC Bayern München'),
    ];

    // **Der kommende Spieltag liegt in der Zukunft** — nur so ist `started`
    // falsch und die Prognose überhaupt sichtbar. Ein festes Datum wäre
    // irgendwann Vergangenheit; deshalb relativ zu jetzt.
    final anpfiff = DateTime.now().add(const Duration(days: 3));
    final spiele = [
      spielMit('Borussia Dortmund', 'FC Bayern München', anpfiff, 4,
          FixtureStatus.scheduled),
      // Zwei abgepfiffene Spieltage davor: Ohne gewertete Runden gibt es
      // weder Schnitte noch eine messbare Streuung — und damit kein Band.
      spielMit('Borussia Dortmund', 'VfB Stuttgart',
          DateTime.now().subtract(const Duration(days: 14)), 2,
          FixtureStatus.finished, 2, 1),
      spielMit('FC Bayern München', 'SC Freiburg',
          DateTime.now().subtract(const Duration(days: 7)), 3,
          FixtureStatus.finished, 1, 0),
    ];

    // Zwei gewertete Spieltage mit unterschiedlichen Werten je Manager —
    // gleiche Zahlen ergäben eine Streuung von null, und das Band bliebe weg.
    final saison = <int, Map<String, PlayerMatchStats>>{
      2: {
        for (final p in meine)
          p.id: const PlayerMatchStats(minutes: 90, played: true, goals: 1),
        for (final p in seine)
          p.id: const PlayerMatchStats(minutes: 70, played: true),
      },
      3: {
        for (final p in meine)
          p.id: const PlayerMatchStats(minutes: 60, played: true),
        for (final p in seine)
          p.id: const PlayerMatchStats(minutes: 90, played: true, assists: 1),
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          draftLeagueProvider.overrideWith((ref, id) => Stream.value(liga)),
          myFantasyLeaguesProvider.overrideWith((ref) => Stream.value([liga])),
          fantasyCurrentRoundProvider.overrideWith((ref) async => 4),
          fantasyManagersProvider.overrideWith(
            (ref, id) => Stream.value(const [
              FantasyManager(userId: 'ich', username: 'SFV03', draftPosition: 1),
              FantasyManager(
                  userId: 'gegner',
                  username: 'lennartruepke',
                  draftPosition: 2),
            ]),
          ),
          leagueTradesProvider.overrideWith((ref, id) => Stream.value(const [])),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          rosterMovesProvider.overrideWith((ref, id) => Stream.value(const [])),
          playerPoolProvider.overrideWith((ref) async => [...meine, ...seine]),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith(
            (ref, id) => Stream.value([
              for (final p in meine)
                RosterEntry(
                    managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
              for (final p in seine)
                RosterEntry(
                    managerId: 'gegner', playerId: p.id, acquiredVia: 'draft'),
            ]),
          ),
          leagueLineupsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          roundStatsProvider.overrideWith((ref, round) async => const {}),
          seasonStatsProvider.overrideWith((ref) async => saison),
          absencesProvider.overrideWith((ref) => Stream.value(const {})),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
          fantasyTipRoundProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FantasyLeagueScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // **Messungen vor dem Bild.** Ein Golden zeigt, wie es aussah, nicht dass
    // die Zahlen ankommen.
    expect(find.text('PROGNOSE'), findsOneWidget,
        reason: 'ohne Kennzeichnung liest man die Zahlen als Punktestand');
    expect(find.textContaining('%'), findsWidgets,
        reason: 'die Siegchance steht an beiden Rändern');

    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(FantasyLeagueScreen),
      matchesGoldenFile('goldens/liga_uebersicht_prognose.png'),
    );
  });
}
