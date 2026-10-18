import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/app/widgets/pill_selector.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/data/fantasy_league_repository.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/formation_umbau.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/lineup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Formation auch während des Spieltags** (auf Ansage, 17.10.2026): Wer
/// schon gespielt hat, ist fest in der Elf; Formationen, die ihn
/// herausnehmen müssten, gehen nicht und sind in der Leiste erkennbar.
void main() {
  const gk = PlayerPosition.gk, def = PlayerPosition.def;
  const mid = PlayerPosition.mid, fwd = PlayerPosition.fwd;
  final slots = <PlayerPosition, List<String?>>{
    gk: ['t'],
    def: ['d1', 'd2', 'd3', 'd4'],
    mid: ['m1', 'm2', 'm3', 'm4'],
    fwd: ['s1', 's2'],
  };

  group('Regel', () {
    test('zu viele Gesperrte auf einer Position sperren die Formation', () {
      final fest = {'d1', 'd2', 'd3', 'd4'};
      expect(
          formationGesperrtWeil(
              slots: slots, formation: (3, 5, 2), gesperrt: fest),
          '4 Verteidiger stehen schon fest');
      expect(
          formationGesperrtWeil(
              slots: slots, formation: (4, 3, 3), gesperrt: fest),
          isNull);
      expect(
          formationGesperrtWeil(
              slots: slots, formation: (5, 3, 2), gesperrt: fest),
          isNull);
    });

    test('ohne Sperre geht alles', () {
      expect(
          formationGesperrtWeil(
              slots: slots, formation: (3, 5, 2), gesperrt: const {}),
          isNull);
    });

    test('beim Umbau fällt nie ein Gesperrter heraus', () {
      // 4-4-2 → 4-3-3: Im Mittelfeld haben m3 und m4 gespielt, also geht m2
      // (der hinterste Ungesperrte), nicht m4.
      final neu = umbauAufFormation(
        slots: slots,
        formation: (4, 3, 3),
        torhueter: 1,
        gesperrt: {'m3', 'm4'},
      );
      expect(neu[mid], ['m1', 'm3', 'm4']);
      expect(neu[fwd], ['s1', 's2', null], reason: 'der neue Platz bleibt leer');
      expect(
        faelltRaus(
            slots: slots,
            formation: (4, 3, 3),
            torhueter: 1,
            gesperrt: {'m3', 'm4'}),
        ['m2'],
      );
    });

    test('ohne Sperre bleibt es bei „der letzte der Reihe geht"', () {
      final neu =
          umbauAufFormation(slots: slots, formation: (4, 3, 3), torhueter: 1);
      expect(neu[mid], ['m1', 'm2', 'm3']);
    });
  });

  testWidgets('die Leiste steht während des Spieltags und sperrt, was nicht geht',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    // Breit genug, dass alle neun Formationen der waagerechten Leiste gebaut
    // werden — sonst stünde „4-4-2" außerhalb des Vorrats und wäre nicht zu
    // finden.
    tester.view.physicalSize = const Size(1300 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    const sge = 'Eintracht Frankfurt';
    const fcb = 'FC Bayern München';
    FantasyPlayer p(String id, PlayerPosition pos, String club) =>
        FantasyPlayer(
            id: id,
            name: 'Spieler $id',
            position: pos,
            club: club,
            birthDate: DateTime(1998),
            nationality: 'DE');
    // Die vier Verteidiger spielen für Frankfurt — deren Spiel läuft.
    final pool = [
      p('t', gk, fcb),
      for (final i in [1, 2, 3, 4]) p('d$i', def, sge),
      for (final i in [1, 2, 3, 4, 5]) p('m$i', mid, fcb),
      for (final i in [1, 2, 3]) p('s$i', fwd, fcb),
    ];
    final kader = [
      for (final x in pool)
        RosterEntry(managerId: 'ich', playerId: x.id, acquiredVia: 'draft'),
    ];
    final elf = {'t', 'd1', 'd2', 'd3', 'd4', 'm1', 'm2', 'm3', 'm4', 's1', 's2'};
    final jetzt = DateTime.now();
    Fixture spiel(String id, String h, String a, DateTime k, FixtureStatus st) =>
        Fixture(
          id: id,
          leagueId: 'bundesliga',
          season: 2026,
          round: 3,
          roundName: '3. Spieltag',
          kickoff: k,
          home: TeamRef(id: h, name: h, shortName: h),
          away: TeamRef(id: a, name: a, shortName: a),
          status: st,
        );
    final repo = _Repo(
        SupabaseClient('http://localhost', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false)),
        kader,
        elf);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'ich',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyLeagueRepositoryProvider.overrideWithValue(repo),
        playerPoolProvider.overrideWith((ref) async => pool),
        clubIconsProvider.overrideWith((ref) async => const {}),
        fantasySeasonFixturesProvider.overrideWith((ref) async => [
              spiel('sportmonks:1', sge, 'SC Freiburg',
                  jetzt.subtract(const Duration(minutes: 40)),
                  FixtureStatus.live),
              spiel('sportmonks:2', fcb, 'VfB Stuttgart',
                  jetzt.add(const Duration(days: 1)),
                  FixtureStatus.scheduled),
            ]),
        fantasyAufstellungsRundeProvider.overrideWith((ref) async => 3),
        roundStatsProvider.overrideWith((ref, r) async => const {}),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: LineupEditor(
              league: FantasyLeague(
                id: 'l1',
                name: 'Liga',
                mode: FantasyMode.liga,
                season: 2026,
                pickTime: DraftPickTime.h2,
                scoring: const FantasyScoringRules(),
                roster: RosterConfig.standard,
                inviteCode: 'X',
                draftStatus: DraftStatus.done,
                createdBy: 'ich',
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    PillChip chip(String fm) => tester.widget<PillChip>(find.ancestor(
        of: find.text(fm), matching: find.byType(PillChip)));
    expect(chip('4-4-2').selected, isTrue, reason: 'die aktuelle');
    expect(chip('3-5-2').gedaempft, isTrue,
        reason: 'vier Verteidiger haben gespielt, drei Plätze reichen nicht');
    expect(chip('4-3-3').gedaempft, isFalse);

    // Gesperrt: Ein Tipp ändert nichts.
    await tester.tap(find.text('3-5-2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(chip('4-4-2').selected, isTrue);
    expect(find.textContaining('geht nicht mehr'), findsOneWidget);

    // Erlaubt: Umbau, die Verteidiger bleiben.
    await tester.tap(find.text('4-3-3'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(chip('4-3-3').selected, isTrue);
  });
}

class _Repo extends FantasyLeagueRepository {
  _Repo(super.client, this._kader, this._elf);
  final List<RosterEntry> _kader;
  final Set<String> _elf;

  @override
  Future<void> setLineup(String leagueId, int round, List<String> ids) async {}

  @override
  Stream<List<RosterEntry>> rosterStream(String leagueId) =>
      Stream.value(_kader);

  @override
  Stream<List<FantasyLineup>> lineupsStream(String leagueId) => Stream.value(
      [FantasyLineup(managerId: 'ich', round: 3, playerIds: _elf)]);
}
