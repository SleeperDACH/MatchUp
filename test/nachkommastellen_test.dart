import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/weekly_recap_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Keine Zahl auf dem Schirm trägt einen Fließkomma-Rattenschwanz.**
///
/// Gemeldet, zum wiederholten Mal: „Im Wochenrecap sind NACH WIE VOR Zahlen mit
/// dutzend Nachkommastellen." Die bisherige Wache
/// (`punkte_formatierung_test.dart`) liest den Quelltext und sucht nach
/// Bezeichnern, die **nach Punkten klingen** — `points`, `pts`, `punkte`,
/// `total`, `score`, `summe`. Sie hat den Fehler fünfmal durchgelassen, zuletzt
/// bei `margin`: Der Vorsprung eines Duells ist ein `double`, heißt aber nicht
/// nach Punkten.
///
/// **Eine Wache, die Namen rät, ist nur so gut wie die Fantasie ihres Autors.**
/// Dieser Test rät nicht: Er baut den Schirm mit Werten, die garantiert einen
/// Rattenschwanz erzeugen (lauter Summen aus 0,4 und 1,5), und liest
/// anschließend **jeden Text im Baum**. Wie die Zahl heißt, aus der er entsteht,
/// ist ihm gleich.
///
/// Wer einen weiteren Schirm absichern will, baut ihn hier auf und ruft
/// [pruefeNachkommastellen] — mehr braucht es nicht.
final _rattenschwanz = RegExp(r'\d[.,]\d{3,}');

void pruefeNachkommastellen(WidgetTester tester) {
  final schlimm = <String>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final t = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (_rattenschwanz.hasMatch(t)) schlimm.add(t);
  }
  expect(schlimm, isEmpty,
      reason: 'Diese Texte tragen mehr als zwei Nachkommastellen — sie kommen '
          'aus roher Interpolation eines `double` statt aus `formatPoints` '
          'oder `Punktzahl`');
}

FantasyPlayer _p(String id, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1998),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  /// Baut den Rückblick mit Werten, die garantiert krumm werden.
  Future<void> baueRueckblick(WidgetTester tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 1400 * 3);
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
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'm0',
      maxTeams: 10,
      tipEnabled: false,
    );

    const namen = ['SFV03', 'JojoAcz44', 'ana', 'Majusch'];
    final manager = [
      for (final (i, n) in namen.indexed)
        FantasyManager(userId: 'm$i', username: n, draftPosition: i + 1),
    ];

    // **Werte, die garantiert krumm werden.** Fouls geben −0,4 und
    // Torschussvorlagen 1,5; elf Spieler mit unterschiedlich vielen davon
    // ergeben Summen wie 12,399999999999999.
    final pool = <FantasyPlayer>[];
    final roster = <RosterEntry>[];
    final stats = <String, PlayerMatchStats>{};
    for (var m = 0; m < namen.length; m++) {
      for (var i = 0; i < 11; i++) {
        final pos = i == 0
            ? PlayerPosition.gk
            : i < 5
                ? PlayerPosition.def
                : i < 9
                    ? PlayerPosition.mid
                    : PlayerPosition.fwd;
        final id = 'm$m-p$i';
        pool.add(_p(id, pos));
        roster.add(
            RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'));
        stats[id] = PlayerMatchStats(
          minutes: 90,
          played: true,
          fouls: (m + i) % 5,
          keyPasses: (m * 2 + i) % 4,
          possessionLost: (m + i * 3) % 7,
        );
      }
    }
    final lineups = [
      for (var m = 0; m < namen.length; m++)
        FantasyLineup(
          managerId: 'm$m',
          round: 1,
          playerIds: {for (var i = 0; i < 11; i++) 'm$m-p$i'},
        ),
    ];
    final spiele = [
      Fixture(
        id: 'sportmonks:1',
        leagueId: 'bundesliga',
        season: 2026,
        round: 1,
        roundName: 'Spieltag 1',
        kickoff: DateTime(2026, 8, 29, 15, 30),
        home: const TeamRef(id: 'FC Test', name: 'FC Test', shortName: 'TES'),
        away: const TeamRef(id: 'FC Zwei', name: 'FC Zwei', shortName: 'ZWE'),
        status: FixtureStatus.finished,
      ),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'm0',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(manager)),
        playerPoolProvider.overrideWith((ref) async => pool),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value(roster)),
        leagueLineupsProvider.overrideWith((ref, id) => Stream.value(lineups)),
        clubIconsProvider.overrideWith((ref) async => const {}),
        roundStatsProvider.overrideWith((ref, r) async => stats),
        fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
        fantasyCurrentRoundProvider.overrideWith((ref) async => 1),
        fantasyRecapRundeProvider.overrideWith((ref) async => 1),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: WeeklyRecapScreen(league: liga, initialRound: 1),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Vorbedingung: Es steht überhaupt etwas da. Ohne die wäre jede Prüfung
    // darauf auf einem leeren Schirm still grün — genau der Fehler, den sie
    // fangen soll, versteckt sich in Zahlen, die es geben muss.
    expect(find.textContaining('SFV03'), findsWidgets,
        reason: 'Der Rückblick muss Inhalt haben, sonst prüft der Test nichts');
  }

  testWidgets('Wochenrückblick zeigt keine krummen Zahlen', (tester) async {
    await baueRueckblick(tester);
    pruefeNachkommastellen(tester);
  });

  testWidgets('Vorschau: Wochenrückblick', (tester) async {
    // **Der Schirm hatte keine Vorschau** — und drei gemeldete Fehler in
    // Folge: krumme Zahlen, ein falsch gerechneter Kader und farbige
    // Kartenränder. Jetzt gibt es ein Bild.
    await baueRueckblick(tester);
    await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/wochenrueckblick.png'));
  });
}
