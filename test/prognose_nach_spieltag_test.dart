import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';
import 'package:matchup/features/fantasy/ui/matchup_hero.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

/// **Nach dem letzten Abpfiff steht die Prognose von vor dem Spieltag**
/// (19.10.2026, auf Ansage). Sie wird nachgerechnet, nicht gespeichert —
/// gehalten wird hier, dass dabei dieselbe Zahl herauskommt wie vor dem
/// Anpfiff, obwohl inzwischen der Spieltag selbst in der Statistik steht und
/// ein Spieler sich verletzt hat.
FantasyPlayer _p(String id, String club) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: PlayerPosition.mid,
      club: club,
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

Fixture _spiel(int runde, DateTime anpfiff, FixtureStatus status) => Fixture(
      id: 'sportmonks:$runde',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: '$runde. Spieltag',
      kickoff: anpfiff,
      status: status,
      home: const TeamRef(id: 'h', name: 'FC Bayern München', shortName: 'FCB'),
      away: const TeamRef(id: 'a', name: 'Borussia Dortmund', shortName: 'BVB'),
    );

const _gut = PlayerMatchStats(minutes: 90, played: true, goals: 1);
const _maessig = PlayerMatchStats(minutes: 90, played: true);

void main() {
  final heimSpieler = [_p('h1', 'FC Bayern München')];
  final gastSpieler = [_p('g1', 'Borussia Dortmund')];
  MatchupSideData seite(List<FantasyPlayer> elf, double punkte) =>
      MatchupSideData(elf, const [], {for (final p in elf) p.id: punkte},
          punkte * elf.length, {for (final p in elf) p.id});

  final anpfiff6 = DateTime(2026, 10, 18, 15, 30);
  final regeln = FantasyScoringRules.standard;

  // Vor dem Spieltag: Spieltag 5 gewertet, 6 noch offen.
  final vorher = duellPrognose(
    round: 6,
    heim: seite(heimSpieler, 0),
    gast: seite(gastSpieler, 0),
    spiele: [
      _spiel(5, anpfiff6.subtract(const Duration(days: 7)),
          FixtureStatus.finished),
      _spiel(6, anpfiff6, FixtureStatus.scheduled),
    ],
    saisonGewertet: {
      5: {'h1': _gut, 'g1': _maessig},
    },
    regeln: regeln,
    ausfaelle: const {},
    wochenStreuung: 20,
    jetzt: anpfiff6.subtract(const Duration(hours: 5)),
  );

  test('vor dem Anpfiff gibt es eine Prognose', () {
    expect(vorher.heimErwartet, isNotNull);
    expect(vorher.gastErwartet, isNotNull);
  });

  test('nach dem Spieltag dieselbe Zahl wie vorher', () {
    final nachher = duellPrognose(
      round: 6,
      // Jetzt mit echten Punkten aus dem Spieltag …
      heim: seite(heimSpieler, 3),
      gast: seite(gastSpieler, 40),
      spiele: [
        _spiel(5, anpfiff6.subtract(const Duration(days: 7)),
            FixtureStatus.finished),
        _spiel(6, anpfiff6, FixtureStatus.finished),
      ],
      // … Spieltag 6 steht in der Statistik …
      saisonGewertet: {
        5: {'h1': _gut, 'g1': _maessig},
        6: {'h1': _maessig, 'g1': _gut},
      },
      regeln: regeln,
      // … und der Heimspieler hat sich im Spiel verletzt.
      ausfaelle: {
        'h1': PlayerAbsence(
          playerId: 'h1',
          gesperrt: false,
          seit: anpfiff6.add(const Duration(minutes: 30)),
        ),
      },
      wochenStreuung: 20,
      jetzt: anpfiff6.add(const Duration(days: 1)),
    );
    expect(nachher.heimErwartet, vorher.heimErwartet);
    expect(nachher.gastErwartet, vorher.gastErwartet);
  });

  test('ein Ausfall von vor dem Spieltag zählt weiter', () {
    final ausfall = {
      'h1': PlayerAbsence(
        playerId: 'h1',
        gesperrt: true,
        seit: anpfiff6.subtract(const Duration(days: 3)),
      ),
    };
    final vorherMitAusfall = duellPrognose(
      round: 6,
      heim: seite(heimSpieler, 0),
      gast: seite(gastSpieler, 0),
      spiele: [_spiel(6, anpfiff6, FixtureStatus.scheduled)],
      saisonGewertet: {
        5: {'h1': _gut, 'g1': _maessig},
      },
      regeln: regeln,
      ausfaelle: ausfall,
      wochenStreuung: 20,
      jetzt: anpfiff6.subtract(const Duration(hours: 1)),
    );
    final nachherMitAusfall = duellPrognose(
      round: 6,
      heim: seite(heimSpieler, 0),
      gast: seite(gastSpieler, 12),
      spiele: [_spiel(6, anpfiff6, FixtureStatus.finished)],
      saisonGewertet: {
        5: {'h1': _gut, 'g1': _maessig},
        6: {'g1': _gut},
      },
      regeln: regeln,
      ausfaelle: ausfall,
      wochenStreuung: 20,
      jetzt: anpfiff6.add(const Duration(days: 1)),
    );
    expect(nachherMitAusfall.heimErwartet, vorherMitAusfall.heimErwartet);
  });
}
