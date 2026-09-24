import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/aufstellungs_prognose.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/player_profile_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Ein Profil, das aus einem Profil heraus geöffnet wird, legt sich **darüber**
/// — es ersetzt es nicht.
///
/// Gemeldet: „Wenn ich über die Aufstellung in ein anderes
/// Spielerprofil gehe und dann runterwische, bin ich komplett raus aus dem
/// Tab." Der Grund war ein `pop` vor dem Öffnen: Das erste Blatt war weg,
/// bevor das zweite kam, und die Wischgeste hatte nichts mehr, wohin sie
/// zurückführen konnte.
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
  // **Deutsche Datumsdaten, sonst wirft der Aufstellungs-Reiter.**
  //
  // Seit dieser Test über die Aufstellung statt über den Kader ins zweite
  // Profil geht, baut er `_PrognoseKopf` — und der formatiert ein Datum auf
  // Deutsch. Ohne diese Zeile scheitert er mit `LocaleDataException`.
  //
  // **Allein lief er trotzdem grün**, und das war die eigentliche Falle: Im
  // Gesamtlauf hatte eine andere Datei die Daten im selben Prozess längst
  // geladen. Ein grüner Einzellauf beweist hier also nichts.
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  const club = 'Borussia Dortmund';
  final held = _p('p1', 'Nico Schlotterbeck', PlayerPosition.def, club);
  final zweiter = _p('p2', 'Gregor Kobel', PlayerPosition.gk, club);
  final pool = [held, zweiter];

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
      id: 'sportmonks:3',
      leagueId: 'bundesliga',
      season: 2026,
      round: 3,
      roundName: 'Spieltag 3',
      kickoff: DateTime(2026, 9, 5, 15, 30),
      home: const TeamRef(id: 'bvb', name: club, shortName: 'BVB'),
      away: const TeamRef(
          id: 'fcb', name: 'FC Bayern München', shortName: 'FCB'),
      status: FixtureStatus.scheduled,
    ),
  ];

  Widget rahmen() => ProviderScope(
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
          seasonStatsProvider.overrideWith((ref) async => const {}),
          // **Der Einstieg ins zweite Profil ist jetzt die Aufstellung.**
          //
          // Bis zum 19.09.2026 führte der Kader-Reiter dorthin; er ist durch
          // die Tabelle ersetzt. Die Zusage, die dieser Test hält, gilt
          // unverändert — ein aus einem Profil geöffnetes Profil legt sich
          // **über** das erste —, nur der Weg dorthin ist ein anderer. Ohne
          // gemeldete Elf stünde im Reiter kein Name zum Antippen.
          prognoseElfProvider.overrideWith(
            (ref, k) async => PrognoseElf(
              club: club,
              bestaetigt: true,
              elf: [
                for (final (i, p) in pool.indexed)
                  PrognoseSpieler(
                    playerId: p.id,
                    name: p.name,
                    formationsPosition: i + 1,
                    reihe: i + 1,
                    spalte: 1,
                  ),
              ],
            ),
          ),
          absencesProvider.overrideWith((ref) => Stream.value(const {})),
          leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [
                RosterEntry(
                    managerId: 'ich', playerId: 'p1', acquiredVia: 'draft'),
              ])),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
          waiverPlayersProvider
              .overrideWith((ref, id) => Stream.value(const <String>{})),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlayerProfile(
                  context,
                  league: liga,
                  player: held,
                  clubIcon: null,
                  isMine: true,
                ),
                child: const Text('öffnen'),
              ),
            ),
          ),
        ),
      );

  testWidgets('Aus dem Aufstellungs-Reiter heraus bleibt das erste Profil stehen',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    await tester.tap(find.text('öffnen'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(BottomSheet), findsOneWidget);

    await tester.tap(find.text('Aufstellung'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // **Auf dem Feld steht der Name gekürzt** („Gregor Kobel" → „G.
    // Kobel", siehe `_kurzerName`): In einen Kreis von 50 Punkten passt
    // nichts Längeres. Der volle Name steht in der Kopfzeile des Blatts —
    // darauf prüft die Erwartung unten.
    await tester.tap(find.text('G. Kobel'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(BottomSheet), findsNWidgets(2),
        reason: 'Das zweite Profil legt sich über das erste, statt es zu '
            'ersetzen');

    // Der Wisch nach unten — hier als Tipp auf den Vorhang über dem obersten
    // Blatt, was denselben Weg nimmt.
    await tester.tapAt(const Offset(200, 12));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(BottomSheet), findsOneWidget,
        reason: 'Zurück beim ersten Profil, nicht draußen im Reiter');
    expect(find.text('Nico Schlotterbeck'), findsWidgets);
  });

  testWidgets('Ein eigener Spieler behält seinen Droppen-Knopf',
      (tester) async {
    // Die Liste gab pauschal `isMine: false` weiter; damit fehlte am
    // eigenen Spieler genau der Knopf, für den man hineingeht.
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    await tester.tap(find.text('öffnen'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Vom eigenen Spieler zu Kobel und zurück zu sich selbst.
    await tester.tap(find.text('Aufstellung'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('G. Kobel'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('Aufstellung').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.text('N. Schlotterbeck').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(BottomSheet), findsNWidgets(3));
    expect(find.widgetWithText(OutlinedButton, 'Droppen'), findsWidgets);
  });
}
