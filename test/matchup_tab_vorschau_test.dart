import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/manager_profile_screen.dart';
import 'package:matchup/features/fantasy/ui/matchup_hero.dart';
import 'package:matchup/features/fantasy/ui/matchups_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des **ganzen MatchUp-Tabs mitten im Spieltag** — nach dem Umbau
/// nach Sleeper (14.10.2026):
///   flutter test --update-goldens test/matchup_tab_vorschau_test.dart
///
/// Ein Spiel ist beendet, eins läuft, eins steht noch aus. Nur so stehen alle
/// Zustände in einem Bild: Stand und Hochrechnung im Kasten, die Siegchance,
/// die Bilanz mit Serie, und auf den Karten Ergebnis, laufender Stand und
/// Anstoß.
///
/// Die Anpfiffe hängen an `DateTime.now()` (der Schirm rechnet damit, ob ein
/// Spiel läuft) — der Bildvergleich läuft deshalb nur mit `--update-goldens`.
/// Was gehalten werden muss, steht als Zusicherung davor.
const _vereine = [
  'FC Bayern München',
  'Borussia Dortmund',
  'RB Leipzig',
  '1. FSV Mainz 05',
  'SC Freiburg',
  'VfB Stuttgart',
];

const _namen = ['SFV03', 'Lewin9', 'ana', 'tamara'];

final _jetzt = DateTime.now();

List<Fixture> _spielplan() {
  Fixture f(int runde, int i, DateTime anpfiff, FixtureStatus status,
          [int? h, int? a]) =>
      Fixture(
        id: 'sportmonks:$runde$i',
        leagueId: 'bundesliga',
        season: 2026,
        round: runde,
        roundName: '$runde. Spieltag',
        kickoff: anpfiff,
        home: TeamRef(id: 'h$i', name: _vereine[i * 2], shortName: 'H'),
        away: TeamRef(id: 'a$i', name: _vereine[i * 2 + 1], shortName: 'A'),
        status: status,
        homeScore: h,
        awayScore: a,
      );
  return [
    for (var r = 1; r <= 2; r++)
      for (var i = 0; i < 3; i++)
        f(r, i, _jetzt.subtract(Duration(days: 21 - r * 7)),
            FixtureStatus.finished, 1, 1),
    // Spieltag 3: beendet · läuft · steht aus.
    f(3, 0, _jetzt.subtract(const Duration(hours: 3)), FixtureStatus.finished,
        2, 1),
    f(3, 1, _jetzt.subtract(const Duration(minutes: 40)), FixtureStatus.live,
        1, 0),
    f(3, 2, _jetzt.add(const Duration(hours: 3)), FixtureStatus.scheduled),
  ];
}

Widget _rahmen() {
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
    maxTeams: 4,
  );
  final manager = [
    for (var i = 0; i < _namen.length; i++)
      FantasyManager(userId: 'm$i', username: _namen[i], draftPosition: i + 1),
  ];
  const nachnamen = [
    'Neuer', 'Kimmich', 'Upamecano', 'Raum', 'Mittelstädt', //
    'Musiala', 'Brandt', 'Nmecha', 'Grüll', 'Kane', 'Guirassy',
  ];
  final pool = <FantasyPlayer>[];
  final roster = <RosterEntry>[];
  final lineups = <FantasyLineup>[];
  for (var m = 0; m < _namen.length; m++) {
    final ids = <String>{};
    for (var i = 0; i < 11; i++) {
      final pos = i == 0
          ? PlayerPosition.gk
          : i < 5
              ? PlayerPosition.def
              : i < 9
                  ? PlayerPosition.mid
                  : PlayerPosition.fwd;
      final id = 'm$m-p$i';
      ids.add(id);
      pool.add(FantasyPlayer(
        id: id,
        name: '${String.fromCharCode(65 + m)}. ${nachnamen[i]}',
        position: pos,
        // Die Vereine reihum, damit jede Seite Spieler in allen drei Spielen
        // hat — beendet, laufend, ausstehend.
        club: _vereine[(i + m) % _vereine.length],
        birthDate: DateTime(1999),
        nationality: 'DE',
      ));
      roster.add(
          RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'));
    }
    // Zwei auf der Bank — damit der Schnitt dort im Bild steht.
    for (final (j, name, pos) in [
      (11, 'Ersatz', PlayerPosition.def),
      (12, 'Joker', PlayerPosition.fwd),
    ]) {
      final id = 'm$m-p$j';
      pool.add(FantasyPlayer(
        id: id,
        name: '${String.fromCharCode(65 + m)}. $name',
        position: pos,
        club: _vereine[(j + m) % _vereine.length],
        birthDate: DateTime(1999),
        nationality: 'DE',
      ));
      roster.add(
          RosterEntry(managerId: 'm$m', playerId: id, acquiredVia: 'draft'));
    }
    for (var r = 1; r <= 3; r++) {
      lineups.add(FantasyLineup(managerId: 'm$m', round: r, playerIds: ids));
    }
  }
  // Zwei gewertete Spieltage für Schnitte, Streuung und Bilanz.
  PlayerMatchStats s(int g, int a) =>
      PlayerMatchStats(minutes: 90, goals: g, assists: a, played: true);
  final saison = <int, Map<String, PlayerMatchStats>>{
    for (var r = 1; r <= 2; r++)
      r: {
        for (var m = 0; m < _namen.length; m++)
          for (var i = 0; i < 13; i++)
            'm$m-p$i': s((i + m + r) % 5 == 0 ? 1 : 0, (i + r) % 4 == 0 ? 1 : 0),
      },
  };
  // Spieltag 3: Wer in einem beendeten oder laufenden Spiel steht, hat Daten.
  final heute = <String, PlayerMatchStats>{
    for (final p in pool)
      if (_vereine.indexOf(p.club) < 4)
        p.id: PlayerMatchStats(
          minutes: _vereine.indexOf(p.club) < 2 ? 90 : 40,
          goals: p.name.contains('Kane') ? 2 : 0,
          assists: p.name.contains('Musiala') ? 1 : 0,
          yellow: p.name.contains('Kimmich') ? 1 : 0,
          saves: p.position == PlayerPosition.gk ? 4 : 0,
          played: true,
        ),
  };
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => User(
          id: 'm0',
          appMetadata: const {},
          userMetadata: const {},
          aud: 'authenticated',
          createdAt: DateTime(2026).toIso8601String(),
        ),
      ),
      fantasyManagersProvider.overrideWith((ref, id) => Stream.value(manager)),
      playerPoolProvider.overrideWith((ref) async => pool),
      leagueRosterProvider.overrideWith((ref, id) => Stream.value(roster)),
      leagueLineupsProvider.overrideWith((ref, id) => Stream.value(lineups)),
      clubIconsProvider.overrideWith((ref) async => const {}),
      seasonStatsProvider
          .overrideWith((ref) async => {...saison, 3: heute}),
      roundStatsProvider.overrideWith(
          (ref, r) async => r == 3 ? heute : (saison[r] ?? const {})),
      fantasySeasonFixturesProvider.overrideWith((ref) async => _spielplan()),
      fantasyCurrentRoundProvider.overrideWith((ref) async => 3),
      absencesProvider.overrideWith((ref) => Stream.value(const {})),
      // Die Streuung (und damit die Siegchance) sucht die Liga unter den
      // eigenen — in der App steht sie dort immer.
      myFantasyLeaguesProvider.overrideWith((ref) => Stream.value([liga])),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: MatchupsBody(league: liga)),
    ),
  );
}

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: MatchUp-Tab mitten im Spieltag', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 1560 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_rahmen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Läuft der Spieltag, steht die Hochrechnung unter dem Stand und die
    // Siegchance an jeder Seite.
    expect(find.textContaining('Prognose '), findsWidgets);
    expect(find.textContaining('% SIEG'), findsWidgets);
    expect(find.text('LIVE'), findsWidgets);
    // Der Wechsler sitzt über der Startelf.
    expect(find.text('STARTELF'), findsOneWidget);
    expect(find.text('Spieltag 3'), findsOneWidget);
    // Auf den Karten: Ergebnis, laufender Stand, Anstoß — und Statistik.
    expect(find.textContaining('vs BVB'), findsWidgets);
    expect(find.textContaining('2 Tore'), findsWidgets);
    // Auch die Bank trägt ihren Schnitt.
    expect(find.text('Bank'), findsOneWidget);

    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(MatchupsBody),
      matchesGoldenFile('goldens/matchup_tab.png'),
    );
  });

  testWidgets('Name im Kasten öffnet das Ligaprofil', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 1560 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_rahmen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // Der eigene Kasten steht vorn: SFV03 gegen den Gegner des Spieltags.
    final kasten = find.byType(MatchupBanner).first;
    final gegner = find.descendant(
      of: kasten,
      matching: find.byWidgetPredicate((w) =>
          w is Text && _namen.skip(1).contains(w.data)),
    );
    expect(gegner, findsOneWidget);
    final name = (tester.widget(gegner) as Text).data!;
    // Ohne Backend: Das Profil lässt dann den Freundschafts-Knopf weg, der
    // sonst Supabase selbst anfragt.
    AppConfig.supabaseInitialized = false;
    await tester.tap(gegner);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final profil = tester.widget<ManagerProfileScreen>(
        find.byType(ManagerProfileScreen));
    expect(profil.managerName, name);
  });
}
