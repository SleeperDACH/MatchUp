import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/data/fantasy_league_repository.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/lineup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **Eine Lücke in der Elf bleibt leer** — live gemeldet am 17.10.2026.
///
/// Nach einem Drop (Potulski raus, Uduokhai rein) stand die gespeicherte Elf
/// bei zehn Spielern. Der Editor füllte den freien Platz mit dem nächsten
/// Bankspieler auf — Mario Götze, dessen Spiel schon gelaufen war. Er
/// punktete nicht (der Server kannte ihn nicht), ließ sich nicht entfernen
/// (gesperrt), und jede weitere Änderung scheiterte, weil sie ihn nachträglich
/// in die Elf geschrieben hätte.
///
/// Nachgestellt: zehn gespeicherte Spieler, auf der Bank ein Mittelfeldspieler
/// eines Vereins, dessen Spiel läuft.

class _Repo extends FantasyLeagueRepository {
  _Repo(super.client);

  final versuche = <List<String>>[];

  @override
  Future<void> setLineup(String leagueId, int round, List<String> ids) async {
    versuche.add(ids);
  }

  @override
  Stream<List<RosterEntry>> rosterStream(String leagueId) =>
      Stream.value(_kader);

  @override
  Stream<List<FantasyLineup>> lineupsStream(String leagueId) =>
      Stream.value([
        FantasyLineup(managerId: 'ich', round: 3, playerIds: _gespeichert),
      ]);
}

FantasyPlayer _p(String id, PlayerPosition pos, String club) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: club,
      birthDate: DateTime(1998, 3, 4),
      nationality: 'DE',
    );

const _bayern = 'FC Bayern München';
const _frankfurt = 'Eintracht Frankfurt';

final _pool = <FantasyPlayer>[
  _p('gk1', PlayerPosition.gk, _bayern),
  for (var i = 1; i <= 4; i++) _p('def$i', PlayerPosition.def, _bayern),
  for (var i = 1; i <= 3; i++) _p('mid$i', PlayerPosition.mid, _bayern),
  // Der Bankspieler, dessen Spiel schon läuft — Götze.
  _p('goetze', PlayerPosition.mid, _frankfurt),
  for (var i = 1; i <= 2; i++) _p('fwd$i', PlayerPosition.fwd, _bayern),
  _p('neu', PlayerPosition.def, _bayern),
];

final _kader = <RosterEntry>[
  for (final p in _pool)
    RosterEntry(managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
];

/// 4-4-2 mit einem fehlenden Mittelfeldspieler — der gedroppte.
final _gespeichert = {
  'gk1', 'def1', 'def2', 'def3', 'def4', 'mid1', 'mid2', 'mid3', 'fwd1', 'fwd2',
};

void main() {
  testWidgets('der freie Platz wird nicht mit einem Bankspieler gefüllt',
      (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final jetzt = DateTime.now();
    Fixture spiel(String id, String heim, String gast, DateTime anpfiff,
            FixtureStatus st) =>
        Fixture(
          id: id,
          leagueId: 'bundesliga',
          season: 2026,
          round: 3,
          roundName: '3. Spieltag',
          kickoff: anpfiff,
          home: TeamRef(id: heim, name: heim, shortName: heim),
          away: TeamRef(id: gast, name: gast, shortName: gast),
          status: st,
        );
    final spiele = [
      // Götzes Spiel läuft schon …
      spiel('sportmonks:1', _frankfurt, 'SC Freiburg',
          jetzt.subtract(const Duration(minutes: 50)), FixtureStatus.live),
      // … das der übrigen kommt erst.
      spiel('sportmonks:2', _bayern, 'VfB Stuttgart',
          jetzt.add(const Duration(days: 1)), FixtureStatus.scheduled),
    ];

    final client = SupabaseClient('http://localhost', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final repo = _Repo(client);
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
        playerPoolProvider.overrideWith((ref) async => _pool),
        clubIconsProvider.overrideWith((ref) async => const {}),
        fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
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

    // Wer steht auf dem Feld? Gesucht in den Feldplätzen — die Bank trägt
    // seit dem 17.10.2026 dieselbe Kachel.
    final aufDemFeld = {
      for (final w in tester.widgetList<Text>(find.descendant(
        of: find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_Slot'),
        matching: find.byType(Text),
      )))
        ?w.data,
    };
    expect(aufDemFeld, isNot(contains('GOETZE')),
        reason: 'der Bankspieler darf nicht von selbst in die Elf rücken');
    expect(aufDemFeld, containsAll(['MID1', 'MID2', 'MID3']));
    expect(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_LeererPlatz'),
      findsOneWidget,
      reason: 'der gedroppte Platz bleibt sichtbar leer',
    );
    expect(repo.versuche, isEmpty,
        reason: 'ohne Zutun wird nichts gespeichert');
  });
}
