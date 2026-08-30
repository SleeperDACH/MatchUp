import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/free_agency_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Free Agency** — und zwar wegen der drei Zustände, die eine
/// Zeile am rechten Rand annehmen kann. Auf dem Gerät sieht man sie nie
/// nebeneinander: Ob ein Verein gerade spielt, hängt am Kalender.
///
/// Anlass war die Meldung „der Waiver funktioniert nicht": Ein Spieler, dessen
/// Partie schon lief, trug dasselbe grüne Plus wie ein freier — man konnte ihn
/// holen, und es passierte nichts.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 6, 1),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Free Agency', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const gespielt = '1. FSV Mainz 05';   // Spieltag 1 am Samstag gelaufen
    const spaeter = 'FC Augsburg';        // spielt erst Sonntag 15:30
    const ruht = 'AS Monaco';             // keine Ansetzung

    final pool = [
      _p('a', 'Hyun-seok Hong', PlayerPosition.fwd, gespielt),
      _p('b', 'Andreas Hanche-Olsen', PlayerPosition.def, gespielt),
      _p('c', 'Young-woo Seol', PlayerPosition.def, spaeter),
      _p('d', 'Marius Wolf', PlayerPosition.mid, spaeter),
      _p('e', 'Denis Zakaria', PlayerPosition.mid, ruht),
    ];

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 10,
      tipEnabled: true,
    );

    Fixture f(String h, String a, FixtureStatus st, DateTime k) => Fixture(
          id: 'sportmonks:${h.hashCode}',
          leagueId: 'bundesliga',
          season: 2026,
          round: 1,
          roundName: 'Spieltag 1',
          kickoff: k,
          home: TeamRef(id: h, name: h, shortName: h),
          away: TeamRef(id: a, name: a, shortName: a),
          status: st,
        );
    // Der Spieltag läuft noch: Mainz ist durch, Augsburg kommt erst.
    final spiele = [
      f(gespielt, 'Paderborn', FixtureStatus.finished,
          DateTime.now().subtract(const Duration(days: 1))),
      f(spaeter, 'FC Schalke 04', FixtureStatus.scheduled,
          DateTime.now().add(const Duration(hours: 8))),
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
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
          // Ein Spieler liegt zusätzlich auf dem Wire — damit im Bild steht,
          // wie sich „Waiver" und „Spiel läuft" unterscheiden.
          waiverPlayersProvider.overrideWith((ref, id) => Stream.value({'e'})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
          absencesProvider.overrideWith((ref) => Stream.value({
                'c': const PlayerAbsence(
                    playerId: 'c',
                    gesperrt: false,
                    grundQuelle: 'Knee Injury'),
                'd': const PlayerAbsence(
                    playerId: 'd',
                    gesperrt: true,
                    grundQuelle: 'Red Card Suspension'),
              })),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FreeAgencyScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(FreeAgencyScreen),
      matchesGoldenFile('goldens/free_agency_vorschau.png'),
    );
  });

  testWidgets('Vorschau: Waiver-Antrag bei vollem Kader', (tester) async {
    // **Der Zustand, in dem der Antrag scheiterte.** Bei vollem Kader verlangt
    // das Blatt einen Abgang, und der Bestätigen-Knopf bleibt bis dahin grau.
    // Gemeldet als „ich habe einen Antrag gestellt, er wird nicht angezeigt".
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const gespielt = '1. FSV Mainz 05';
    final zugang = _p('neu', 'Andreas Hanche-Olsen', PlayerPosition.def, gespielt);

    // Ein voller Kader: 16 Spieler.
    final meine = [
      for (var i = 0; i < 16; i++)
        _p('m$i', 'Mein Spieler $i',
            PlayerPosition.values[i % PlayerPosition.values.length],
            'FC Augsburg')
    ];

    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 10,
      tipEnabled: true,
    );

    final spiele = [
      Fixture(
        id: 'sportmonks:1',
        leagueId: 'bundesliga',
        season: 2026,
        round: 1,
        roundName: 'Spieltag 1',
        kickoff: DateTime.now().subtract(const Duration(days: 1)),
        home: const TeamRef(id: 'm', name: gespielt, shortName: 'M05'),
        away: const TeamRef(id: 'p', name: 'Paderborn', shortName: 'SCP'),
        status: FixtureStatus.finished,
      ),
      Fixture(
        id: 'sportmonks:2',
        leagueId: 'bundesliga',
        season: 2026,
        round: 1,
        roundName: 'Spieltag 1',
        kickoff: DateTime.now().add(const Duration(hours: 8)),
        home: const TeamRef(id: 'a', name: 'FC Augsburg', shortName: 'FCA'),
        away: const TeamRef(id: 's', name: 'FC Schalke 04', shortName: 'S04'),
        status: FixtureStatus.scheduled,
      ),
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
          playerPoolProvider.overrideWith((ref) async => [zugang, ...meine]),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value([
                for (final p in meine)
                  RosterEntry(
                      managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
              ])),
          waiverPlayersProvider
              .overrideWith((ref, id) => Stream.value(const <String>{})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FreeAgencyScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Den goldenen Antragsknopf des angepfiffenen Spielers drücken.
    await tester.tap(find.byIcon(Icons.schedule).last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile('goldens/waiver_antrag_voller_kader.png'),
    );

    // Und mit gewähltem Abgang: Der Hinweis verschwindet, „Bestätigen" wird
    // bedienbar. Ohne diesen zweiten Blick wüsste man nicht, ob die Auswahl
    // überhaupt ankommt — genau daran hing der gemeldete Fehler.
    await tester.tap(find.text('Mein Spieler 0'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await expectLater(
      find.byType(BottomSheet),
      matchesGoldenFile('goldens/waiver_antrag_abgang_gewaehlt.png'),
    );

    final knopf = tester.widget<FilledButton>(
        find.ancestor(of: find.text('Bestätigen'), matching: find.byType(FilledButton)));
    expect(knopf.onPressed, isNotNull,
        reason: 'Mit gewähltem Abgang muss abgeschickt werden können');
  });

  testWidgets('Ein Tipp auf den Namen öffnet das Spielerprofil',
      (tester) async {
    // Vorher reagierte die Zeile gar nicht — nur der Knopf rechts tat etwas.
    // Wer entscheiden soll, ob er einen Spieler holt, braucht aber Leistung,
    // Spielplan und die voraussichtliche Aufstellung.
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final held = _p('x', 'Andreas Hanche-Olsen', PlayerPosition.def,
        '1. FSV Mainz 05');
    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'ich',
      maxTeams: 10,
      tipEnabled: true,
    );

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
          playerPoolProvider.overrideWith((ref) async => [held]),
          clubIconsProvider.overrideWith((ref) async => const {}),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
          leagueLineupsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          waiverPlayersProvider
              .overrideWith((ref, id) => Stream.value(const <String>{})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          seasonStatsProvider.overrideWith((ref) async => const {}),
          prognoseElfProvider.overrideWith((ref, k) async => null),
          fantasySeasonFixturesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: FreeAgencyScreen(league: liga),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('Andreas Hanche-Olsen'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'Der Name muss das Profil öffnen');
    // Die Reiter des Profils belegen, dass wirklich das Profil offen ist und
    // nicht irgendein Blatt.
    expect(find.text('Aufstellung'), findsOneWidget);
    expect(find.text('Spielplan'), findsOneWidget);
  });
}
