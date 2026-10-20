import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/logic/round_robin.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/draft_order.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/reset_draft.dart';
import 'package:matchup/features/fantasy/logic/transfer_vorgaenge.dart';
import 'package:matchup/features/fantasy/logic/wertungs_kader.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/draft_start.dart';

import 'support/schrift.dart';

/// **Reset zur Winterpause** (20.10.2026, Migration 0143).
///   flutter test --update-goldens test/reset_winterpause_test.dart
FantasyPlayer _p(String id, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1998),
      nationality: 'DE',
    );

FantasyLeague _liga({
  DraftStatus status = DraftStatus.done,
  String phase = 'startup',
  bool reset = true,
  DateTime? erfolgt,
}) =>
    FantasyLeague(
      id: 'l1',
      name: 'Test',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: status,
      createdBy: 'm1',
      maxTeams: 4,
      draftPhase: phase,
      resetAktiv: reset,
      resetErfolgtAt: erfolgt,
    );

void main() {
  setUpAll(ladeSchrift);

  group('Liga', () {
    test('Termin, Änderbarkeit, Zustände', () {
      expect(FantasyLeague.resetTermin(2026), DateTime(2026, 12, 24));
      final l = _liga();
      expect(l.resetAenderbar(DateTime(2026, 12, 23, 23)), isTrue);
      expect(l.resetAenderbar(DateTime(2026, 12, 24)), isFalse);
      expect(_liga(erfolgt: DateTime(2026, 12, 24)).resetAenderbar(
          DateTime(2026, 11, 1)), isFalse);

      final wartet =
          _liga(status: DraftStatus.reset, phase: 'reset', erfolgt: DateTime(2026, 12, 24));
      expect(wartet.imReset, isTrue);
      expect(wartet.saisonGestartet, isTrue,
          reason: 'Tabelle und Rückblick gelten weiter');
      final draft = _liga(
          status: DraftStatus.drafting, phase: 'reset', erfolgt: DateTime(2026, 12, 24));
      expect(draft.imReset, isTrue);
      final ersterDraft = _liga(status: DraftStatus.drafting);
      expect(ersterDraft.imReset, isFalse);
      expect(ersterDraft.saisonGestartet, isFalse);
    });

    test('liest die Spalten aus 0143', () {
      final l = FantasyLeague.fromJson({
        'id': 'l1',
        'name': 'Test',
        'mode': 'liga',
        'season': 2026,
        'draft_pick_seconds': 60,
        'invite_code': 'x',
        'draft_status': 'reset',
        'created_by': 'm1',
        'draft_phase': 'reset',
        'reset_aktiv': true,
        'reset_erfolgt_at': '2026-12-23T23:00:00Z',
      });
      expect(l.draftStatus, DraftStatus.reset);
      expect(l.draftPhase, 'reset');
      expect(l.resetAktiv, isTrue);
      expect(l.resetErfolgtAt, isNotNull);
    });
  });

  group('Reset-Draft', () {
    test('Tabellenletzter pickt zuerst', () {
      // h2hStandings liefert den Ersten vorn.
      const tabelle = [
        H2HRecord(managerId: 'erster', wins: 3),
        H2HRecord(managerId: 'zweiter', wins: 2),
        H2HRecord(managerId: 'dritter', wins: 1),
        H2HRecord(managerId: 'letzter'),
      ];
      expect(resetReihenfolge(tabelle),
          ['letzter', 'dritter', 'zweiter', 'erster']);
    });

    test('Snake über die Reset-Position, die Draft-Position bleibt', () {
      const managers = [
        FantasyManager(userId: 'a', username: 'A', draftPosition: 1, resetPosition: 4),
        FantasyManager(userId: 'b', username: 'B', draftPosition: 2, resetPosition: 3),
        FantasyManager(userId: 'c', username: 'C', draftPosition: 3, resetPosition: 2),
        FantasyManager(userId: 'd', username: 'D', draftPosition: 4, resetPosition: 1),
      ];
      final sicht = managerFuerDraft(managers, 'reset');
      // Runde 1: d c b a — Runde 2: a b c d.
      final folge = [
        for (var i = 0; i < 8; i++) currentManager(sicht, i)!.userId,
      ];
      expect(folge, ['d', 'c', 'b', 'a', 'a', 'b', 'c', 'd']);
      // Die echten Positionen (an ihnen hängen die Duelle) sind unberührt.
      expect(managers.map((m) => m.draftPosition), [1, 2, 3, 4]);
      expect(managerFuerDraft(managers, 'startup'), same(managers));
    });

    test('Picks je Phase', () {
      const picks = [
        DraftPick(pickNumber: 1, round: 1, managerId: 'a', playerId: 'x', isAuto: false),
        DraftPick(
            pickNumber: 1, round: 1, managerId: 'd', playerId: 'x', isAuto: false,
            phase: 'reset'),
      ];
      expect(picksDerPhase(picks, 'reset').single.managerId, 'd');
      expect(picksDerPhase(picks, 'startup').single.managerId, 'a');
    });
  });

  group('Die Tabelle bleibt', () {
    final elf = <FantasyPlayer>[
      _p('gk', PlayerPosition.gk),
      for (var i = 0; i < 4; i++) _p('def$i', PlayerPosition.def),
      for (var i = 0; i < 4; i++) _p('mid$i', PlayerPosition.mid),
      for (var i = 0; i < 2; i++) _p('fwd$i', PlayerPosition.fwd),
    ];
    final neu = <FantasyPlayer>[
      _p('ngk', PlayerPosition.gk),
      for (var i = 0; i < 4; i++) _p('ndef$i', PlayerPosition.def),
      for (var i = 0; i < 4; i++) _p('nmid$i', PlayerPosition.mid),
      for (var i = 0; i < 2; i++) _p('nfwd$i', PlayerPosition.fwd),
    ];
    final byId = {for (final p in [...elf, ...neu]) p.id: p};
    // Spieltag 14: nur die alten Spieler haben getroffen — die neuen auch,
    // aber für ein anderes Team.
    const tor = PlayerMatchStats(minutes: 90, played: true, goals: 1);
    final stats = {for (final p in [...elf, ...neu]) p.id: tor};
    final liga = _liga();

    // Protokoll: Draft-Zugänge, dann der Reset (alle ab), dann der neue Draft.
    final moves = [
      for (final (i, p) in elf.indexed)
        RosterMove(
            id: i, leagueId: 'l1', managerId: 'm1', playerId: p.id,
            zugang: true, passiertAm: DateTime(2026, 8, 20), weg: 'draft'),
      for (final (i, p) in elf.indexed)
        RosterMove(
            id: 100 + i, leagueId: 'l1', managerId: 'm1', playerId: p.id,
            zugang: false, passiertAm: DateTime(2026, 12, 24), weg: 'reset'),
    ];
    final aktuell = [
      for (final p in neu.take(5))
        RosterEntry(managerId: 'm1', playerId: p.id, acquiredVia: 'draft'),
    ];
    final wk = WertungsKader(aktuell,
        vorReset: kaderVorReset(moves), ersteRundeNachReset: 15);

    double summe(List<RosterEntry> roster, int runde) => effectiveTotalsForRound(
          stats: stats,
          round: runde,
          managers: const [FantasyManager(userId: 'm1', username: 'Eric')],
          roster: roster,
          playerById: byId,
          lineups: const [], // keine gespeicherte Elf → beste Elf aus dem Kader
          scoring: liga.scoring,
          rosterConfig: liga.roster,
        )['m1']!;

    test('Spieltag 14 ohne gespeicherte Elf wertet den Kader vor dem Reset', () {
      final vorher = summe([
        for (final p in elf)
          RosterEntry(managerId: 'm1', playerId: p.id, acquiredVia: 'draft'),
      ], 14);
      expect(summe(wk, 14), vorher,
          reason: 'dieselbe Summe wie vor dem Reset — die Tabelle bleibt');
      expect(summe(aktuell, 14), lessThan(vorher),
          reason: 'Gegenprobe: mit dem neuen Kader wäre die Hinrunde anders');
    });

    test('ab der Rückrunde zählt der neue Kader', () {
      expect(summe(wk, 15), summe(aktuell, 15));
      expect(wk, hasLength(5), reason: 'nach außen der aktuelle Kader');
    });

    test('erste Runde nach dem Termin', () {
      Fixture f(int r, DateTime k) => Fixture(
            id: 'f$r',
            leagueId: 'bundesliga',
            season: 2026,
            round: r,
            roundName: '$r',
            kickoff: k,
            home: const TeamRef(id: 'h', name: 'H', shortName: 'H'),
            away: const TeamRef(id: 'a', name: 'A', shortName: 'A'),
            status: FixtureStatus.scheduled,
          );
      expect(
          ersteRundeNachReset([
            f(14, DateTime(2026, 12, 19)),
            f(16, DateTime(2027, 1, 13)),
            f(15, DateTime(2027, 1, 9)),
          ], FantasyLeague.resetTermin(2026)),
          15);
    });

    test('der Reset erscheint nicht als Wechsel', () {
      expect(ereignisseAus(moves).where((e) => e.passiertAm.month == 12), isEmpty);
    });
  });

  testWidgets('Vorschau: Start-Blatt des Reset-Drafts', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final liga = _liga(
        status: DraftStatus.reset, phase: 'reset', erfolgt: DateTime(2026, 12, 24));
    const folge = [
      FantasyManager(userId: 'd', username: 'Tabellenletzter'),
      FantasyManager(userId: 'c', username: 'JojoAcz'),
      FantasyManager(userId: 'b', username: 'lennartruepke'),
      FantasyManager(userId: 'a', username: 'SFV03'),
    ];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        resetReihenfolgeProvider.overrideWith((ref, id) => folge),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(folge)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => draftStartenMitBestaetigung(context, ref, liga),
                child: const Text('los'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('RESET-DRAFT STARTEN?'), findsOneWidget);
    expect(find.text('Nach Tabelle'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('Tabellenletzter'), findsOneWidget);
    expect(find.text('Zufällig'), findsNothing,
        reason: 'die Reihenfolge steht fest');
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/reset_draft_start.png'));
  });
}
