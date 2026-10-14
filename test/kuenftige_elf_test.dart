import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

/// **Ein künftiger Spieltag bekommt die zuletzt gestellte Elf**, nicht eine
/// beliebige.
///
/// Ohne gespeicherte Aufstellung nahm `computeSideData` die beste Elf nach den
/// Punkten **dieses** Spieltags — für einen Spieltag in der Zukunft alle null,
/// die Auswahl war also Zufall, und die Prognose für die nächsten MatchUps
/// rechnete mit irgendwelchen elf Spielern.
void main() {
  const roster = RosterConfig(
    gk: 1, def: 4, mid: 4, fwd: 2, bench: 5, //
    defMin: 3, defMax: 5, midMin: 2, midMax: 5, fwdMin: 1, fwdMax: 4,
  );
  final liga = FantasyLeague(
    id: 'l1',
    name: 'Liga',
    mode: FantasyMode.liga,
    season: 2026,
    pickTime: DraftPickTime.h2,
    scoring: const FantasyScoringRules(),
    roster: roster,
    inviteCode: 'X',
    draftStatus: DraftStatus.done,
    createdBy: 'm',
    maxTeams: 4,
  );
  FantasyPlayer p(String id, PlayerPosition pos) => FantasyPlayer(
        id: id,
        name: 'Spieler $id',
        position: pos,
        club: 'FC Bayern München',
        nationality: 'de',
        birthDate: DateTime(2000),
      );
  final kader = [
    p('gk1', PlayerPosition.gk),
    p('gk2', PlayerPosition.gk),
    for (var i = 0; i < 6; i++) p('d$i', PlayerPosition.def),
    for (var i = 0; i < 6; i++) p('m$i', PlayerPosition.mid),
    for (var i = 0; i < 4; i++) p('f$i', PlayerPosition.fwd),
  ];
  final byId = {for (final x in kader) x.id: x};
  final rosterEintraege = [
    for (final x in kader)
      RosterEntry(managerId: 'm', playerId: x.id, acquiredVia: 'draft'),
  ];
  // Gestellt am 2. Spieltag: der zweite Torwart, die hinteren Verteidiger.
  final gestellt = {
    'gk2', 'd2', 'd3', 'd4', 'd5', 'm2', 'm3', 'm4', 'm5', 'f2', 'f3', //
  };
  final lineups = [FantasyLineup(managerId: 'm', round: 2, playerIds: gestellt)];

  test('künftiger Spieltag ohne Daten: die zuletzt gestellte Elf', () {
    final seite = computeSideData(
      league: liga,
      round: 5,
      managerId: 'm',
      byId: byId,
      roster: rosterEintraege,
      lineups: lineups,
      stats: const <String, PlayerMatchStats>{},
    );
    expect(seite.starters.map((x) => x.id).toSet(), gestellt);
  });

  test('gespielter Spieltag ohne gestellte Elf: weiter die beste', () {
    // Dort gibt es Daten, und gewertet wird ohne Aufstellung die beste Elf —
    // dieselbe Regel wie in `effectiveTotalsForRound`.
    final seite = computeSideData(
      league: liga,
      round: 1,
      managerId: 'm',
      byId: byId,
      roster: rosterEintraege,
      lineups: lineups,
      stats: const {'gk1': PlayerMatchStats(minutes: 90, saves: 6)},
    );
    expect(seite.starters.map((x) => x.id), contains('gk1'));
    expect(seite.starters.map((x) => x.id), isNot(contains('gk2')));
  });
}
