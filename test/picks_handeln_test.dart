import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/draft_rechte.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/draft_room_screen.dart';
import 'package:matchup/features/fantasy/ui/meine_picks.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// **Picks für den Reset-Draft handeln** (0145, 20.10.2026). Dieselben Regeln
/// stehen in SQL (`fantasy_pick_besitzer`, `fantasy_current_manager`); laufen
/// sie auseinander, zeigt der Draft-Raum einen anderen Manager am Zug, als
/// der Server ziehen lässt.
///   flutter test --update-goldens test/picks_handeln_test.dart
void main() {
  setUpAll(ladeSchrift);

  // Folge der ersten Runde: Tabellenletzter zuerst.
  const folge = ['c', 'b', 'a'];

  group('resetPicks', () {
    test('Snake: Runde 1 vorwärts, Runde 2 rückwärts', () {
      final alle = resetPicks(reihenfolge: folge, runden: 2, rechte: const {});
      expect([for (final p in alle) '${p.code}:${p.ursprung}'], [
        '1.01:c', '1.02:b', '1.03:a',
        '2.01:a', '2.02:b', '2.03:c',
      ]);
      expect(alle.every((p) => p.besitzer == p.ursprung), isTrue);
    });

    test('ein gehandelter Pick gehört dem neuen Besitzer', () {
      final rechte = rechteKarte(const [
        DraftRecht(runde: 1, ursprung: 'c', besitzer: 'a'),
      ]);
      final alle = resetPicks(reihenfolge: folge, runden: 2, rechte: rechte);
      expect([for (final p in picksVon(alle, 'a')) p.code],
          ['1.01', '1.03', '2.01']);
      expect([for (final p in picksVon(alle, 'c')) p.code], ['2.03']);
      expect(alle.first.gehandelt, isTrue);
    });
  });

  group('amZugMitRechten', () {
    final managers = [
      for (final (i, id) in folge.indexed)
        FantasyManager(userId: id, username: id, draftPosition: i + 1),
    ];

    test('ohne Handel zieht das Team der Position', () {
      expect(amZugMitRechten(managers, 0, const {})?.userId, 'c');
      expect(amZugMitRechten(managers, 3, const {})?.userId, 'a');
    });

    test('mit Handel zieht der Besitzer', () {
      final rechte = rechteKarte(const [
        DraftRecht(runde: 1, ursprung: 'c', besitzer: 'a'),
        DraftRecht(runde: 2, ursprung: 'a', besitzer: 'b'),
      ]);
      expect(amZugMitRechten(managers, 0, rechte)?.userId, 'a');
      expect(amZugMitRechten(managers, 1, rechte)?.userId, 'b');
      // Runde 2, erster Pick: Position 3 = a, gehört jetzt b.
      expect(amZugMitRechten(managers, 3, rechte)?.userId, 'b');
    });

    test('Besitzer nicht mehr in der Liga: das ursprüngliche Team zieht', () {
      final rechte = rechteKarte(const [
        DraftRecht(runde: 1, ursprung: 'c', besitzer: 'weg'),
      ]);
      expect(amZugMitRechten(managers, 0, rechte)?.userId, 'c');
    });
  });

  test('picksHandelbar: nur Hinrunde einer Liga mit Reset', () {
    FantasyLeague liga({
      bool reset = true,
      DraftStatus status = DraftStatus.done,
      DateTime? erfolgt,
    }) =>
        FantasyLeague(
          id: 'l',
          name: 'L',
          mode: FantasyMode.liga,
          season: 2026,
          pickTime: DraftPickTime.h2,
          scoring: const FantasyScoringRules(),
          roster: RosterConfig.standard,
          inviteCode: 'X',
          draftStatus: status,
          createdBy: 'a',
          resetAktiv: reset,
          resetErfolgtAt: erfolgt,
        );
    expect(picksHandelbar(liga()), isTrue);
    expect(picksHandelbar(liga(reset: false)), isFalse);
    expect(picksHandelbar(liga(status: DraftStatus.setup)), isFalse);
    expect(picksHandelbar(liga(erfolgt: DateTime(2026, 12, 24))), isFalse);
  });

  testWidgets('Vorschau: Board mit gehandeltem Pick, eigene Picks', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 760 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final managers = [
      const FantasyManager(userId: 'c', username: 'lennart', draftPosition: 1),
      const FantasyManager(userId: 'b', username: 'eric', draftPosition: 2),
      const FantasyManager(userId: 'a', username: 'SFV03', draftPosition: 3),
    ];
    final rechte = rechteKarte(const [
      DraftRecht(runde: 1, ursprung: 'c', besitzer: 'a'),
      DraftRecht(runde: 2, ursprung: 'a', besitzer: 'b'),
    ]);
    final liga = FantasyLeague(
      id: 'l1',
      name: 'MatchUp! #1',
      mode: FantasyMode.liga,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'X',
      draftStatus: DraftStatus.done,
      createdBy: 'a',
      resetAktiv: true,
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'a',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyManagersProvider
            .overrideWith((ref, id) => Stream.value(managers)),
        resetPicksProvider.overrideWith((ref, id) =>
            resetPicks(reihenfolge: folge, runden: 4, rechte: rechte)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 300,
                child: DraftBoard(
                  picks: const [],
                  playerById: const {},
                  managers: managers,
                  maxTeams: 3,
                  rounds: 4,
                  currentManagerId: null,
                  currentRound: 0,
                  myId: 'a',
                  showPlaceholders: false,
                  rechte: rechte,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: MeinePicks(league: liga, kompakt: true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: MeinePicks(league: liga),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: PickKachel(
                    runde: 1, team: 'lennart', code: '1.01', hervor: true),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // **Kopf und Felder fluchten** — der Kopf trug einmal mehr Außenabstand,
    // und je Spalte verrutschte das Raster um einen Punkt.
    Rect kasten(Finder text) => tester.getRect(
        find.ancestor(of: text, matching: find.byType(Container)).first);
    for (final (kopf, feld) in [
      ('lennart', '1.01'),
      ('eric', '1.02'),
      ('SFV03', '1.03'),
    ]) {
      final k = kasten(find.text(kopf).first);
      final f = kasten(find.text(feld).first);
      expect(k.left, closeTo(f.left, 0.5), reason: kopf);
      expect(k.width, closeTo(f.width, 0.5), reason: kopf);
    }

    // Auf dem Board steht der neue Besitzer in der Zelle des gehandelten Picks.
    expect(find.text('SFV03'), findsWidgets);
    // Ein erhandelter eigener Pick heißt „Dein Pick", nicht der eigene Name.
    expect(find.text('Dein Pick'), findsOneWidget);
    // Eigene Picks: 1.01 (erhandelt), 1.03, 3.03, 4.01 — 2.03 ist an eric.
    expect(find.text('1.01'), findsWidgets);
    expect(find.text('von lennart'), findsOneWidget);
    expect(find.textContaining('1 abgegeben'), findsOneWidget);

    await expectLater(
        find.byType(Scaffold), matchesGoldenFile('goldens/picks_handeln.png'));
  });
}
