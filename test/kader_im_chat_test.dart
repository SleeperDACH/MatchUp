import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/chat_message.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/fantasy_chat_screen.dart';
import 'package:matchup/features/fantasy/ui/kader_meldung.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Kaderbewegungen im Liga-Chat (auf Ansage, 17.10.2026, nach Sleeper):
/// Free Agency, Waiver und Trades stehen als Meldung mit Spielerkarte
/// zwischen den Nachrichten.
final _jetzt = DateTime(2026, 10, 17, 15);

RosterMove _m(int id, String mgr, String spieler, bool rein, String? weg,
        DateTime wann) =>
    RosterMove(
      id: id,
      leagueId: 'l1',
      managerId: mgr,
      playerId: spieler,
      zugang: rein,
      weg: weg,
      passiertAm: wann,
    );

final _t1 = _jetzt.subtract(const Duration(hours: 5));
final _t2 = _jetzt.subtract(const Duration(hours: 3));
final _t3 = _jetzt.subtract(const Duration(hours: 1));

final _moves = <RosterMove>[
  // Draft — gehört nicht in den Chat.
  _m(1, 'a', 'p9', true, 'draft', _jetzt.subtract(const Duration(days: 40))),
  // Free Agency: einer rein, einer raus.
  _m(2, 'a', 'p1', true, 'fa', _t1),
  _m(3, 'a', 'p2', false, null, _t1),
  // Waiver.
  _m(4, 'b', 'p3', true, 'waiver', _t2),
  _m(5, 'b', 'p4', false, null, _t2),
  // Trade: beide Seiten im selben Augenblick.
  _m(6, 'a', 'p5', true, 'trade', _t3),
  _m(7, 'a', 'p6', false, 'trade', _t3),
  _m(8, 'b', 'p6', true, 'trade', _t3),
  _m(9, 'b', 'p5', false, 'trade', _t3),
];

FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998),
      nationality: 'DE',
    );

final _pool = [
  _p('p1', 'Felix Uduokhai', PlayerPosition.def, '1. FC Union Berlin'),
  _p('p2', 'Kacper Potulski', PlayerPosition.def, '1. FSV Mainz 05'),
  _p('p3', 'Atakan Karazor', PlayerPosition.mid, 'VfB Stuttgart'),
  _p('p4', 'Dejan Ljubicic', PlayerPosition.mid, '1. FC Köln'),
  _p('p5', 'Serhou Guirassy', PlayerPosition.fwd, 'Borussia Dortmund'),
  _p('p6', 'Nadiem Amiri', PlayerPosition.mid, '1. FSV Mainz 05'),
];

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  test('ohne Draft, ein Trade ist eine Meldung', () {
    final m = kaderMeldungen(_moves);
    expect(m, hasLength(3), reason: 'FA, Waiver, Trade — kein Draft');
    final trade = m.values.where((x) => x.ereignis.istTrade).toList();
    expect(trade, hasLength(1), reason: 'zwei Seiten, eine Meldung');
    expect(m.values.every((x) => x.nachricht.isSystem), isTrue);
  });

  testWidgets('Vorschau: Kaderbewegungen im Liga-Chat', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 1100 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

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
    );
    final nachrichten = [
      ChatMessage(
          id: 'n1',
          userId: 'b',
          body: 'Wer holt eigentlich noch einen Torwart?',
          createdAt: _jetzt.subtract(const Duration(hours: 6))),
      ChatMessage(
          id: 'n2',
          userId: 'a',
          body: 'Uduokhai war zu billig 😄',
          createdAt: _jetzt.subtract(const Duration(hours: 4))),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) => User(
              id: 'a',
              appMetadata: const {},
              userMetadata: const {},
              aud: 'authenticated',
              createdAt: DateTime(2026).toIso8601String(),
            )),
        fantasyMessagesProvider
            .overrideWith((ref, id) => Stream.value(nachrichten)),
        rosterMovesProvider.overrideWith((ref, id) => Stream.value(_moves)),
        fantasyManagersProvider.overrideWith((ref, id) => Stream.value(const [
              FantasyManager(userId: 'a', username: 'MatchUp!'),
              FantasyManager(userId: 'b', username: 'Leonardo'),
            ])),
        playerPoolProvider.overrideWith((ref) async => _pool),
        clubIconsProvider.overrideWith((ref) async => const {}),
        leagueRosterProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        home: FantasyChatScreen(league: liga),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(KaderMeldung), findsNWidgets(3));
    expect(find.text('@MatchUp! hat den Kader geändert.'), findsOneWidget);
    expect(find.text('@Leonardo hat einen Waiver-Antrag gewonnen.'),
        findsOneWidget);
    expect(find.text('@MatchUp! und @Leonardo haben getauscht.'),
        findsOneWidget);
    expect(find.text('F. UDUOKHAI'), findsOneWidget);
    expect(find.text('ABW · FCU'), findsOneWidget);

    // Das Bild trägt Tage relativ zu heute — verglichen wird nur beim
    // Aufnehmen, die Messungen darüber laufen immer.
    if (!autoUpdateGoldenFiles) return;
    await expectLater(find.byType(FantasyChatScreen),
        matchesGoldenFile('goldens/kader_im_chat.png'));
  });
}
