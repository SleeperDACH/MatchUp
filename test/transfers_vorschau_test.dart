import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';
import 'package:matchup/features/fantasy/models/trade.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/transfers_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau des **Transfers-Schirms** — beide Seiten.
///
/// Auf dem Gerät sieht man immer nur eine, und ob überhaupt etwas darin steht,
/// hängt davon ab, was die eigene Liga gerade tut. Genau deshalb gibt es die
/// Bilder: „Meine Transfers" mit allem, was auflaufen kann (eingehendes
/// Angebot, offener Antrag, selbst gestelltes Angebot), und die Liga-Seite mit
/// Zu- und Abgängen mehrerer Manager über zwei Tage.
FantasyPlayer _p(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1999, 2, 3),
      nationality: 'DE',
    );

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  final pool = [
    _p('p1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
    _p('p2', 'Nico Schlotterbeck', PlayerPosition.def, 'Borussia Dortmund'),
    _p('p3', 'Julian Brandt', PlayerPosition.mid, 'Borussia Dortmund'),
    _p('p4', 'Serhou Guirassy', PlayerPosition.fwd, 'Borussia Dortmund'),
    _p('p5', 'Loris Karius', PlayerPosition.gk, 'FC Schalke 04'),
  ];

  final liga = FantasyLeague(
    id: 'l1',
    name: 'MatchUp! #1',
    mode: FantasyMode.liga,
    season: 2026,
    pickTime: DraftPickTime.h2,
    scoring: const FantasyScoringRules(),
    roster: RosterConfig.standard,
    inviteCode: 'ABC',
    draftStatus: DraftStatus.done,
    createdBy: 'ich',
    maxTeams: 10,
    tipEnabled: true,
  );

  const manager = [
    FantasyManager(userId: 'ich', username: 'SFV03', draftPosition: 1),
    FantasyManager(userId: 'gegner', username: 'lennartruepke', draftPosition: 2),
    FantasyManager(userId: 'dritte', username: 'tamara', draftPosition: 3),
  ];

  final trades = [
    TradeOffer(
      id: 't1',
      leagueId: 'l1',
      fromManager: 'gegner',
      toManager: 'ich',
      status: TradeStatus.pending,
      message: 'Wäre das was für dich?',
      createdAt: DateTime(2026, 8, 30, 9),
    ),
    TradeOffer(
      id: 't2',
      leagueId: 'l1',
      fromManager: 'ich',
      toManager: 'dritte',
      status: TradeStatus.pending,
      createdAt: DateTime(2026, 8, 30, 8),
    ),
  ];

  final details = {
    't1': (
      trade: trades[0],
      items: [
        const TradeItem(tradeId: 't1', giver: 'gegner', playerId: 'p4'),
        const TradeItem(tradeId: 't1', giver: 'ich', playerId: 'p1'),
      ],
    ),
    't2': (
      trade: trades[1],
      items: [
        const TradeItem(tradeId: 't2', giver: 'ich', playerId: 'p3'),
        const TradeItem(tradeId: 't2', giver: 'dritte', playerId: 'p5'),
      ],
    ),
  };

  final antraege = [
    WaiverClaim(
      id: 'w1',
      leagueId: 'l1',
      managerId: 'ich',
      addPlayerId: 'p2',
      dropPlayerId: 'p1',
      rank: 1,
      status: WaiverStatus.pending,
      createdAt: DateTime(2026, 8, 30, 7),
    ),
  ];

  final heute = DateTime.now();
  final gestern = heute.subtract(const Duration(days: 1));
  final moves = [
    RosterMove(
        id: 5,
        leagueId: 'l1',
        managerId: 'gegner',
        playerId: 'p5',
        zugang: true,
        weg: 'fa',
        passiertAm: heute.subtract(const Duration(hours: 2))),
    RosterMove(
        id: 4,
        leagueId: 'l1',
        managerId: 'gegner',
        playerId: 'p3',
        zugang: false,
        passiertAm: heute.subtract(const Duration(hours: 2, minutes: 1))),
    RosterMove(
        id: 3,
        leagueId: 'l1',
        managerId: 'ich',
        playerId: 'p4',
        zugang: true,
        weg: 'waiver',
        passiertAm: heute.subtract(const Duration(hours: 6))),
    RosterMove(
        id: 2,
        leagueId: 'l1',
        managerId: 'dritte',
        playerId: 'p2',
        zugang: true,
        weg: 'trade',
        passiertAm: gestern),
    // Draft-Zeilen müssen aus der Liga-Seite herausfallen — sonst begraben sie
    // bei sechzehn Teams jede Meldung darunter.
    RosterMove(
        id: 1,
        leagueId: 'l1',
        managerId: 'dritte',
        playerId: 'p1',
        zugang: true,
        weg: 'draft',
        passiertAm: gestern.subtract(const Duration(days: 3))),
  ];

  Widget rahmen() => ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'ich',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(manager)),
          leagueTradesProvider.overrideWith((ref, id) => Stream.value(trades)),
          tradeDetailProvider.overrideWith((ref, id) async => details[id]),
          myWaiverClaimsProvider
              .overrideWith((ref, id) => Stream.value(antraege)),
          rosterMovesProvider.overrideWith((ref, id) => Stream.value(moves)),
          waiverWindowProvider.overrideWith((ref) async =>
              (round: 2, deadline: DateTime(2026, 9, 3, 15, 30))),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TransfersScreen(league: liga),
        ),
      );

  testWidgets('Vorschau: Transfers', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 950 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(rahmen());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // **Der Bildvergleich läuft nur mit `--update-goldens`.** Die Liga-Seite
    // gruppiert nach „Heute" und „Gestern" und schreibt Uhrzeiten hin — beides
    // aus `DateTime.now()`. Ein fest eingecheckter Vergleich wäre nicht erst
    // am nächsten Tag rot, sondern in der nächsten Minute. Dieselbe
    // Entscheidung wie bei der Home- und der Live-Vorschau.
    if (autoUpdateGoldenFiles) {
      await expectLater(find.byType(TransfersScreen),
          matchesGoldenFile('goldens/transfers_meine.png'));
    }

    // Was gehalten werden muss, steht als **Messung** daneben und läuft bei
    // jedem `flutter test`.
    expect(find.text('Trade-Angebot'), findsWidgets,
        reason: 'Eingehende und selbst gestellte Angebote gehören hierher');
    expect(find.text('Antrag 1'), findsOneWidget,
        reason: 'Offene Waiver-Anträge gehören hierher');

    await tester.tap(find.text('Liga'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (autoUpdateGoldenFiles) {
      await expectLater(find.byType(TransfersScreen),
          matchesGoldenFile('goldens/transfers_liga.png'));
    }

    // **Der Draft darf in der Liga-Liste nicht auftauchen.** Bei sechzehn
    // Teams sind das Hunderte Zeilen, die jede Free-Agency-Meldung darunter
    // begraben; wer den Draft sehen will, hat dafür das Board.
    expect(find.text('Gedraftet'), findsNothing);
    // Zu- und Abgang stehen beide da — der Abgang war vor 0096 nirgends
    // festgehalten, und genau er ist die Hälfte, die man sucht.
    expect(find.textContaining('Verpflichtet'), findsWidgets);
    expect(find.textContaining('Abgegeben'), findsWidgets);
  });
}
