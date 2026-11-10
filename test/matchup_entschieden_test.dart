import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/matchup_hero.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

/// Gemeldet (08.11.2026): Bei einem Team, dessen 11 Spieler alle gespielt
/// haben, stand bis zum Ende des Spieltags „Prognose". Und ein MatchUp, in
/// dem alle 22 durch waren, blieb rot und zeigte „100 % Sieg" für eine Seite —
/// obwohl nach der Remis-Regel schon ein Unentschieden feststand.

FantasyPlayer _p(String id, String club) => FantasyPlayer(
  id: id,
  name: 'Spieler $id',
  position: PlayerPosition.mid,
  club: club,
  nationality: 'de',
  birthDate: DateTime(1998, 5, 4),
);

Fixture _spiel(
  String id,
  String heim,
  String gast,
  DateTime anpfiff,
  FixtureStatus status,
) => Fixture(
  id: 'sportmonks:$id',
  leagueId: 'bundesliga',
  season: 2026,
  round: 10,
  roundName: '10. Spieltag',
  kickoff: anpfiff,
  status: status,
  home: TeamRef(id: heim, name: heim, shortName: heim),
  away: TeamRef(id: gast, name: gast, shortName: gast),
);

MatchupSideData _seite(List<FantasyPlayer> elf, double punkte) =>
    MatchupSideData(
      elf,
      const [],
      {for (final p in elf) p.id: punkte},
      punkte * elf.length,
      {for (final p in elf) p.id},
    );

void main() {
  final samstag = DateTime(2026, 11, 7, 15, 30);
  final sonntag = DateTime(2026, 11, 8, 17, 30);
  final jetzt = DateTime(2026, 11, 7, 18, 0); // Samstag durch, Sonntag offen
  final spiele = [
    _spiel('1', 'FC Bayern München', 'Borussia Dortmund', samstag,
        FixtureStatus.finished),
    _spiel('2', 'SC Freiburg', 'VfB Stuttgart', sonntag,
        FixtureStatus.scheduled),
  ];
  final samstagsElf = [_p('a', 'FC Bayern München'), _p('b', 'Borussia Dortmund')];
  final gemischt = [_p('c', 'FC Bayern München'), _p('d', 'SC Freiburg')];

  group('elfDurch', () {
    test('alle Spiele abgepfiffen: durch', () {
      expect(
        elfDurch(
          seite: _seite(samstagsElf, 5),
          spiele: spiele,
          round: 10,
          jetzt: jetzt,
        ),
        isTrue,
      );
    });

    test('ein Spieler hat noch zu spielen: nicht durch', () {
      expect(
        elfDurch(
          seite: _seite(gemischt, 5),
          spiele: spiele,
          round: 10,
          jetzt: jetzt,
        ),
        isFalse,
      );
    });

    test('hängender Status: nach der sicheren Spieldauer trotzdem durch', () {
      final haengt = [
        _spiel('1', 'FC Bayern München', 'Borussia Dortmund', samstag,
            FixtureStatus.live),
      ];
      expect(
        elfDurch(
          seite: _seite(samstagsElf, 5),
          spiele: haengt,
          round: 10,
          jetzt: samstag.add(const Duration(hours: 4)),
        ),
        isTrue,
      );
    });
  });

  test('duellPrognose meldet je Seite, ob die Elf durch ist', () {
    final p = duellPrognose(
      round: 10,
      heim: _seite(samstagsElf, 5),
      gast: _seite(gemischt, 5),
      spiele: spiele,
      saisonGewertet: {
        9: {
          'a': const PlayerMatchStats(minutes: 90, played: true),
        },
      },
      regeln: FantasyScoringRules.standard,
      ausfaelle: const {},
      wochenStreuung: 20,
      jetzt: jetzt,
    );
    expect(p.heimFertig, isTrue);
    expect(p.gastFertig, isFalse);
  });

  Future<void> zeige(WidgetTester tester, Widget kasten) async {
    await initializeDateFormatting('de_DE');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: Center(child: kasten)),
      ),
    );
    await tester.pump();
  }

  testWidgets('alle 22 durch, Spieltag läuft: Unentschieden statt 100 %', (
    tester,
  ) async {
    await zeige(
      tester,
      const MatchupBanner(
        round: 10,
        homeName: 'Anhm',
        awayName: 'Gegner',
        homePoints: 182.4,
        awayPoints: 180.1,
        homeMe: true,
        awayMe: false,
        live: true, // andere Spiele des Spieltags laufen noch
        started: true,
        remisGrenze: 5,
        homeErwartet: 182.4,
        awayErwartet: 180.1,
        siegchanceHeim: 1,
        homeFertig: true,
        awayFertig: true,
      ),
    );
    expect(find.text('UNENTSCHIEDEN'), findsNWidgets(2));
    expect(find.textContaining('% SIEG'), findsNothing);
    expect(find.textContaining('Prognose'), findsNothing);
  });

  testWidgets('eine Seite durch: dort keine Prognose, das Duell läuft', (
    tester,
  ) async {
    await zeige(
      tester,
      const MatchupBanner(
        round: 10,
        homeName: 'Anhm',
        awayName: 'Gegner',
        homePoints: 182.4,
        awayPoints: 120.0,
        homeMe: true,
        awayMe: false,
        live: true,
        started: true,
        homeErwartet: 182.4,
        awayErwartet: 175.0,
        siegchanceHeim: 0.7,
        homeFertig: true,
        awayFertig: false,
      ),
    );
    // Nur die Gastseite trägt noch eine Prognose.
    expect(find.textContaining('Prognose'), findsOneWidget);
    expect(find.textContaining('182'), findsOneWidget,
        reason: 'die 182,4 steht nur noch als Stand, nicht als Prognose');
    expect(find.textContaining('% SIEG'), findsNWidgets(2));
  });
}
