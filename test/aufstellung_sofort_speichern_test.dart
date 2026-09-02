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

import 'support/schrift.dart';

/// **Ein Wechsel wird sofort gespeichert — und ein Fehlschlag noch einmal
/// versucht.**
///
/// Gemeldet nach dem Spieltag: *„Während des letzten Spieltages gab es
/// häufiger Speicherprobleme bei der Aufstellung. Bitte so umbauen, dass, wenn
/// ein Spieler eingewechselt wird, die Aufstellung gespeichert wird."*
///
/// Zwei Ursachen lagen dahinter, und die zweite ist die schwerere:
///
/// 1. Jede Änderung wartete **700 ms**. Wer wechselt und sofort weiterzieht
///    (Schirm zu, Bildschirmsperre, Funkloch), sah eine Aufstellung, die es
///    nirgends gab.
/// 2. Ein **fehlgeschlagenes** Speichern hatte als einziger Ausgang keinen
///    zweiten Versuch. `laeuftGerade` bestellte sich neu ein, ein fehlender
///    Spieltag auch — nur der Netzfehler zeigte eine Snackbar und war fertig.
///
/// Der Test prüft beides am echten Editor, nicht an der Logik daneben: Die
/// Verzögerung war ein Detail des Widgets, und genau dort fiel sie an.

class _MerkendesRepo extends FantasyLeagueRepository {
  _MerkendesRepo(super.client, {this.scheitertSooft = 0});

  /// Die ersten [scheitertSooft] Versuche schlagen fehl.
  final int scheitertSooft;
  final versuche = <List<String>>[];

  @override
  Future<void> setLineup(String leagueId, int round, List<String> ids) async {
    versuche.add(ids);
    if (versuche.length <= scheitertSooft) throw Exception('Netz weg');
  }

  @override
  Stream<List<RosterEntry>> rosterStream(String leagueId) =>
      Stream.value(_kader);

  @override
  Stream<List<FantasyLineup>> lineupsStream(String leagueId) =>
      Stream.value(const []);
}

const _ligaId = 'l1';

FantasyPlayer _p(String id, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: 'FC Bayern München',
      birthDate: DateTime(1998, 3, 4),
      nationality: 'DE',
    );

/// Ein Kader, der 4-4-2 spielen kann und auf jeder Position eine Reserve hat.
final _pool = <FantasyPlayer>[
  for (var i = 1; i <= 2; i++) _p('gk$i', PlayerPosition.gk),
  for (var i = 1; i <= 5; i++) _p('def$i', PlayerPosition.def),
  for (var i = 1; i <= 5; i++) _p('mid$i', PlayerPosition.mid),
  for (var i = 1; i <= 3; i++) _p('fwd$i', PlayerPosition.fwd),
];

final _kader = <RosterEntry>[
  for (final p in _pool)
    RosterEntry(managerId: 'ich', playerId: p.id, acquiredVia: 'draft'),
];

final _liga = FantasyLeague(
  id: _ligaId,
  name: 'MatchUp! #1',
  mode: FantasyMode.liga,
  season: 2026,
  pickTime: DraftPickTime.h2,
  scoring: const FantasyScoringRules(),
  roster: RosterConfig.standard,
  inviteCode: 'ABC123',
  draftStatus: DraftStatus.done,
  createdBy: 'ich',
  maxTeams: 10,
);

Future<_MerkendesRepo> _aufbauen(WidgetTester tester,
    {int scheitertSooft = 0}) async {
  final vorher = AppConfig.supabaseInitialized;
  AppConfig.supabaseInitialized = true;
  addTearDown(() => AppConfig.supabaseInitialized = vorher);

  tester.view.physicalSize = const Size(402 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final client = SupabaseClient('http://localhost', 'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  final repo = _MerkendesRepo(client, scheitertSooft: scheitertSooft);

  await tester.pumpWidget(
    ProviderScope(
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
        // Kein Spiel läuft: niemand ist gesperrt.
        fantasySeasonFixturesProvider.overrideWith((ref) async => <Fixture>[]),
        fantasyAufstellungsRundeProvider.overrideWith((ref) async => 3),
        roundStatsProvider.overrideWith((ref, r) async => const {}),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: LineupEditor(league: _liga)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Der Tausch-Knopf **an genau diesem Platz**.
///
/// Der Name auf dem Platz öffnet das Profil, nicht die Spielerwahl — dafür
/// gibt es die Positions-Pille daneben. Deshalb erst den Platz über den Namen
/// finden (`AnimatedContainer` ist die Wurzel von `_Slot`), dann darin den
/// Knopf.
Finder _tauschKnopf(String name) => find.descendant(
      of: find
          .ancestor(
              of: find.text(name), matching: find.byType(AnimatedContainer))
          .first,
      matching: find.byIcon(Icons.swap_horiz),
    );

/// Tauscht auf dem Feld einen Spieler über die Spielerwahl aus.
///
/// Auf dem Platz steht nur der **letzte Namensteil** („Spieler def1" → „def1"),
/// deshalb die kurzen Finder.
Future<void> _wechsle(WidgetTester tester, String raus, String rein) async {
  await tester.tap(_tauschKnopf(raus));
  await tester.pumpAndSettle();
  // In der Auswahl steht der volle Name, auf dem Platz nur das letzte Wort.
  await tester.tap(find.text('Spieler $rein'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Ein Wechsel speichert sofort, nicht erst nach 700 ms',
      (tester) async {
    final repo = await _aufbauen(tester);
    final vorher = repo.versuche.length;

    await tester.tap(_tauschKnopf('def1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spieler def5'));
    // **Nur ein Bild weiter** — kein Vorspulen. Genau hier lag die Lücke:
    // Vorher passierte in diesem Moment nichts, und was danach kam
    // (Schirmwechsel, Funkloch), entschied über die Aufstellung.
    await tester.pump();
    await tester.pump();

    expect(repo.versuche.length, vorher + 1,
        reason: 'Der Wechsel muss ohne Wartezeit beim Server sein');
    expect(repo.versuche.last, contains('def5'));
    expect(repo.versuche.last, isNot(contains('def1')));
    expect(repo.versuche.last, hasLength(11));

    await tester.pumpAndSettle();
  });

  testWidgets('Ein Fehlschlag wird erneut versucht', (tester) async {
    final repo = await _aufbauen(tester, scheitertSooft: 2);
    final vorher = repo.versuche.length;

    await _wechsle(tester, 'def1', 'def5');
    expect(repo.versuche.length, vorher + 1, reason: 'erster Versuch');

    // Erste Wiederholung nach 2 s, zweite nach 4 s.
    await tester.pump(const Duration(seconds: 3));
    expect(repo.versuche.length, vorher + 2, reason: 'zweiter Versuch');

    await tester.pump(const Duration(seconds: 5));
    expect(repo.versuche.length, vorher + 3,
        reason: 'dritter Versuch — und der gelingt');
    expect(repo.versuche.last, contains('def5'));

    // Danach ist Ruhe: Ein geglücktes Speichern beendet die Kette.
    await tester.pump(const Duration(seconds: 30));
    expect(repo.versuche.length, vorher + 3);

    await tester.pumpAndSettle();
  });

  testWidgets('Der Formationswechsel behält dieselbe Elf', (tester) async {
    await _aufbauen(tester);

    /// Wer gerade auf dem Platz steht (kurze Namen).
    Set<String> aufDemPlatz() => {
          for (final w in tester.widgetList<Text>(find.byType(Text)))
            if (w.data != null && RegExp(r'^(gk|def|mid|fwd)\d$').hasMatch(w.data!))
              w.data!,
        };

    // Die Saat ist 3-4-3.
    final vorher = aufDemPlatz();
    expect(vorher, hasLength(11));

    await tester.tap(find.text('4-4-2'));
    await tester.pumpAndSettle();

    final nachher = aufDemPlatz();
    // Abwehr wächst um einen (ein Feld bleibt leer), Sturm schrumpft um einen.
    expect(nachher.length, 10, reason: 'ein Platz ist frei, keiner rückt nach');
    expect(nachher.difference(vorher), isEmpty,
        reason: 'es darf niemand Neues hereinkommen — genau das war der Fehler');
    expect(vorher.difference(nachher), {'fwd3'},
        reason: 'der letzte Stürmer der Reihe geht raus');

    // Und weil die Elf jetzt unvollständig ist, sagt die Fußzeile das auch.
    expect(
      find.text('Nicht gespeichert – die Elf ist noch nicht vollständig'),
      findsOneWidget,
    );
  });

  testWidgets('Die Fußzeile sagt, dass ein neuer Versuch läuft',
      (tester) async {
    await _aufbauen(tester, scheitertSooft: 99);
    await _wechsle(tester, 'def1', 'def5');
    await tester.pump();

    expect(find.text('Nicht gespeichert – neuer Versuch läuft'), findsOneWidget,
        reason: '„Speichere …" wäre hier eine Lüge');
  });
}
