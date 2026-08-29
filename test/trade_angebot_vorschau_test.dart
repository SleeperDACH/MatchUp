import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/trade.dart';
import 'package:matchup/features/fantasy/providers.dart';
import 'package:matchup/features/fantasy/ui/trade_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Trade-Angebotskarte**.
///
/// Sie zeigte die Spieler als Komma-Liste von Namen — dieselbe Auskunft wie
/// jetzt, aber ohne Verein, ohne Position und ohne Wiedererkennung. Hier steht
/// das eingehende Angebot (mit Annehmen/Ablehnen) neben dem selbst gestellten;
/// auf dem Gerät sieht man immer nur eins von beiden.
FantasyPlayer _spieler(String id, String name, PlayerPosition pos, String club) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(1998, 3, 4),
      nationality: 'DE',
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Trade-Angebot', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 1180 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final pool = [
      _spieler('p1', 'Jonas Urbig', PlayerPosition.gk, 'FC Bayern München'),
      _spieler('p2', 'Nico Schlotterbeck', PlayerPosition.def,
          'Borussia Dortmund'),
      _spieler('p3', 'Randal Kolo Muani', PlayerPosition.fwd,
          'Eintracht Frankfurt'),
      _spieler('p4', 'Florian Wirtz', PlayerPosition.mid, 'RB Leipzig'),
    ];

    TradeOffer angebot(String id, String von, String an) => TradeOffer(
          id: id,
          leagueId: 'l1',
          fromManager: von,
          toManager: an,
          status: TradeStatus.pending,
          message: id == 't1' ? 'Wäre das was für dich?' : null,
          createdAt: DateTime(2026, 8, 29, 12),
        );

    final details = {
      // Eingehend: Ich bekomme zwei, ich gebe einen.
      't1': (
        trade: angebot('t1', 'gegner', 'ich'),
        items: [
          const TradeItem(tradeId: 't1', giver: 'gegner', playerId: 'p3'),
          const TradeItem(tradeId: 't1', giver: 'gegner', playerId: 'p2'),
          const TradeItem(tradeId: 't1', giver: 'ich', playerId: 'p4'),
        ],
      ),
      // Angenommen, aber noch nicht vollzogen — der Zustand, den es seit
      // Migration 0088 gibt: Waehrend eines laufenden Spieltags wechseln die
      // Kader erst danach.
      't3': (
        trade: TradeOffer(
          id: 't3',
          leagueId: 'l1',
          fromManager: 'ich',
          toManager: 'gegner',
          status: TradeStatus.accepted,
          createdAt: DateTime(2026, 8, 29, 9),
          executeAfter: DateTime(2026, 8, 31, 5, 30),
        ),
        items: [
          const TradeItem(tradeId: 't3', giver: 'ich', playerId: 'p2'),
          const TradeItem(tradeId: 't3', giver: 'gegner', playerId: 'p4'),
        ],
      ),
      // Selbst gestellt: einer gegen einen, dazu ein Spieler, den der
      // lokale Pool nicht kennt.
      't2': (
        trade: angebot('t2', 'ich', 'gegner'),
        items: [
          const TradeItem(tradeId: 't2', giver: 'ich', playerId: 'p1'),
          const TradeItem(
              tradeId: 't2', giver: 'gegner', playerId: 'sportmonks:99999'),
        ],
      ),
    };

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
          playerPoolProvider.overrideWith((ref) async => pool),
          clubIconsProvider.overrideWith((ref) async => const {}),
          fantasyManagersProvider
              .overrideWith((ref, id) => Stream.value(const [])),
          tradeDetailProvider.overrideWith((ref, id) async => details[id]),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: const [
                Text('EINGEHEND',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
                SizedBox(height: 4),
                TradeCard(tradeId: 't1'),
                SizedBox(height: 16),
                Text('SELBST GESTELLT',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
                SizedBox(height: 4),
                TradeCard(tradeId: 't2'),
                SizedBox(height: 16),
                Text('ANGENOMMEN, WARTET AUF DEN SPIELTAG',
                    style: TextStyle(color: Colors.white38, fontSize: 10)),
                SizedBox(height: 4),
                TradeCard(tradeId: 't3'),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(
      find.byType(ListView),
      matchesGoldenFile('goldens/trade_angebot_vorschau.png'),
    );
  });
}
