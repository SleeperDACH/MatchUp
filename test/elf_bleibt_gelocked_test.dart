import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/matchup_lineups.dart';

/// **Die gespeicherte Elf ist die Auskunft, nicht der heutige Kader.**
///
/// Gemeldet: „Wenn man einen Spieler, der am Wochenende in der Startelf stand,
/// droppt, beeinflusst das im Nachhinein die Punkte. Das darf auf keinen Fall
/// passieren."
///
/// Die Wertung filterte die Startelf gegen den **aktuellen** Kader. Wer nach
/// dem Anpfiff abgegeben oder getradet wurde, fiel damit rückwirkend aus der
/// Elf und nahm seine Punkte mit.
FantasyPlayer _p(String id, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1998),
      nationality: 'DE',
    );

void main() {
  final liga = FantasyLeague(
    id: 'l1',
    name: 'Test',
    mode: FantasyMode.liga,
    season: 2026,
    pickTime: DraftPickTime.h2,
    scoring: const FantasyScoringRules(),
    roster: RosterConfig.standard,
    inviteCode: 'ABC',
    draftStatus: DraftStatus.done,
    createdBy: 'm1',
    maxTeams: 10,
    tipEnabled: false,
  );

  // Elf Spieler in gültiger Formation, dazu einer auf der Bank.
  final elf = <FantasyPlayer>[
    _p('gk', PlayerPosition.gk),
    for (var i = 0; i < 4; i++) _p('def$i', PlayerPosition.def),
    for (var i = 0; i < 4; i++) _p('mid$i', PlayerPosition.mid),
    for (var i = 0; i < 2; i++) _p('fwd$i', PlayerPosition.fwd),
  ];
  final bank = _p('bank', PlayerPosition.fwd);
  final byId = {for (final p in [...elf, bank]) p.id: p};

  // Jeder Aufgestellte hat ein Tor gemacht; der Torwart steht zu Null.
  const tor = PlayerMatchStats(minutes: 90, played: true, goals: 1);
  final stats = {for (final p in elf) p.id: tor};

  List<RosterEntry> kader(Iterable<FantasyPlayer> ps) => [
        for (final p in ps)
          RosterEntry(managerId: 'm1', playerId: p.id, acquiredVia: 'draft'),
      ];
  final aufstellung = [
    FantasyLineup(
      managerId: 'm1',
      round: 1,
      playerIds: {for (final p in elf) p.id},
    ),
  ];

  MatchupSideData seite(List<RosterEntry> roster) => computeSideData(
        league: liga,
        round: 1,
        managerId: 'm1',
        byId: byId,
        roster: roster,
        lineups: aufstellung,
        stats: stats,
      );

  test('mit vollem Kader stehen elf Spieler und alle Punkte', () {
    final s = seite(kader([...elf, bank]));
    expect(s.starters, hasLength(11));
    expect(s.total, greaterThan(0));
  });

  test('ein abgegebener Spieler bleibt in der Elf — samt seiner Punkte', () {
    // **Der gemeldete Fall.** fwd0 wurde nach dem Anpfiff getradet: Er steht
    // in keinem Kader mehr, aber in der gespeicherten Elf.
    final voll = seite(kader([...elf, bank]));
    final ohne = seite(kader([...elf.where((p) => p.id != 'fwd0'), bank]));

    expect(ohne.starters, hasLength(11),
        reason: 'Die Elf bleibt eine Elf');
    expect(ohne.starters.map((p) => p.id), contains('fwd0'));
    expect(ohne.total, voll.total,
        reason: 'Ein Trade nach dem Anpfiff darf die Punkte nicht bewegen');
  });

  test('er zählt auch dann, wenn mehrere die Elf verlassen haben', () {
    final voll = seite(kader([...elf, bank]));
    final ohne = seite(kader([
      ...elf.where((p) => p.id != 'fwd0' && p.id != 'def1' && p.id != 'gk'),
      bank,
    ]));
    expect(ohne.starters, hasLength(11));
    expect(ohne.total, voll.total);
  });

  test('die Bank bleibt der heutige Kader', () {
    // Die Bank ist eine Auskunft über das Team von jetzt, keine Wertung —
    // wer weg ist, sitzt nicht mehr darauf.
    final ohne = seite(kader([...elf.where((p) => p.id != 'fwd0'), bank]));
    expect(ohne.bench.map((p) => p.id), ['bank']);
  });

  test('ohne gespeicherte Elf zählt weiter der aktuelle Kader', () {
    // Die beste Elf ist ein Vorschlag für ein Team, das noch nichts gestellt
    // hat — sie muss aus dem Bestand von jetzt kommen.
    final s = computeSideData(
      league: liga,
      round: 1,
      managerId: 'm1',
      byId: byId,
      roster: kader([...elf, bank]),
      lineups: const [],
      stats: stats,
    );
    expect(s.starters, hasLength(11));
  });
  // ---------------------------------------------------------------------
  // Dieselbe Frage an die **Tabelle**, nicht nur an die Aufstellungsansicht.
  //
  // Der erste Anlauf hat nur `computeSideData` korrigiert — die Elf sah danach
  // richtig aus, die Punkte blieben falsch („Erics Punkte hat es nicht
  // geändert"). Die Summe kommt aus `effectiveTotalsForRound`, und die filterte
  // ebenfalls gegen den Kader von jetzt. Zwei Wege, dieselbe Frage; ein Test,
  // der nur einen prüft, sagt nichts.
  // ---------------------------------------------------------------------
  double summe(List<RosterEntry> roster) => effectiveTotalsForRound(
        stats: stats,
        round: 1,
        managers: const [FantasyManager(userId: 'm1', username: 'Eric')],
        roster: roster,
        playerById: byId,
        lineups: aufstellung,
        scoring: liga.scoring,
        rosterConfig: liga.roster,
      )['m1']!;

  test('die Tabellensumme ändert sich durch einen Trade danach nicht', () {
    final voll = summe(kader([...elf, bank]));
    final ohne = summe(kader([...elf.where((p) => p.id != 'fwd0'), bank]));
    expect(voll, greaterThan(0));
    expect(ohne, voll,
        reason: 'Der Aufgestellte punktet weiter für den, der ihn gestellt hat');
  });

  test('auch mehrere Abgänge bewegen die Summe nicht', () {
    final voll = summe(kader([...elf, bank]));
    final ohne = summe(kader([
      ...elf.where((p) => p.id != 'fwd0' && p.id != 'mid2'),
      bank,
    ]));
    expect(ohne, voll);
  });

  test('ohne gestellte Elf zählt weiter der Kader von jetzt', () {
    // Ein Team ohne Aufstellung bekommt die beste Elf — und die kann nur aus
    // dem bestehen, was es hat.
    double ohneElf(List<RosterEntry> roster) => effectiveTotalsForRound(
          stats: stats,
          round: 1,
          managers: const [FantasyManager(userId: 'm1', username: 'Eric')],
          roster: roster,
          playerById: byId,
          lineups: const [],
          scoring: liga.scoring,
          rosterConfig: liga.roster,
        )['m1']!;
    expect(ohneElf(kader([...elf, bank])),
        greaterThan(ohneElf(kader([...elf.take(6), bank]))));
  });
}
