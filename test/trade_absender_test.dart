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

/// **Die Trade-Karte sagt, mit wem man handelt.**
///
/// Gemeldet: *„Wenn man einen Trade bekommt, sieht man in der Box leider
/// nicht, von wem der kommt. Das bitte einbauen."*
///
/// Der Kopf trug „Trade-Angebot" und den Liganamen — beides Auskünfte, die
/// man schon hat, wenn man die Karte überhaupt sieht. Der Absender stand
/// nirgends, obwohl die Karte in **drei** Zusammenhängen auftaucht: in der
/// Direktnachricht, im „Angebote"-Tab und in den Transfers. Nur im Chat
/// konnte man ihn aus dem Gesprächspartner erschließen.
///
/// Der Test fragt beide Richtungen ab **und** den Fall, dass der Mann nicht
/// (mehr) in der Managerliste steht: Dann darf die Karte keinen Namen raten,
/// sondern fällt auf die neutrale Marke zurück.

FantasyPlayer _spieler(String id) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: PlayerPosition.mid,
      club: 'FC Bayern München',
      birthDate: DateTime(1998, 3, 4),
      nationality: 'DE',
    );

TradeOffer _angebot(String id, String von, String an) => TradeOffer(
      id: id,
      leagueId: 'l1',
      fromManager: von,
      toManager: an,
      status: TradeStatus.pending,
      createdAt: DateTime(2026, 8, 29, 12),
    );

const _manager = [
  FantasyManager(userId: 'ich', username: 'SFV03'),
  FantasyManager(userId: 'gegner', username: 'eric', teamName: 'Erics Elf'),
];

Widget _karte(String tradeId,
    {List<FantasyManager> manager = _manager}) {
  final details = {
    // Eingehend: gegner → ich.
    'rein': (
      trade: _angebot('rein', 'gegner', 'ich'),
      items: const [
        TradeItem(tradeId: 'rein', giver: 'gegner', playerId: 'p1'),
        TradeItem(tradeId: 'rein', giver: 'ich', playerId: 'p2'),
      ],
    ),
    // Selbst gestellt: ich → gegner.
    'raus': (
      trade: _angebot('raus', 'ich', 'gegner'),
      items: const [
        TradeItem(tradeId: 'raus', giver: 'ich', playerId: 'p1'),
        TradeItem(tradeId: 'raus', giver: 'gegner', playerId: 'p2'),
      ],
    ),
  };

  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith((ref) => User(
            id: 'ich',
            appMetadata: const {},
            userMetadata: const {},
            aud: 'authenticated',
            createdAt: DateTime(2026).toIso8601String(),
          )),
      playerPoolProvider.overrideWith((ref) async => [_spieler('p1'), _spieler('p2')]),
      clubIconsProvider.overrideWith((ref) async => const {}),
      fantasyManagersProvider.overrideWith((ref, id) => Stream.value(manager)),
      tradeDetailProvider.overrideWith((ref, id) async => details[id]),
    ],
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: ListView(children: [TradeCard(tradeId: tradeId)])),
    ),
  );
}

Future<void> _zeige(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(w);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUpAll(ladeSchrift);

  setUp(() {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
  });

  testWidgets('Eingehend: die Karte nennt den Absender', (tester) async {
    await _zeige(tester, _karte('rein'));

    // Der Liganame (Teamname) steht vorn, nicht der Nutzername.
    expect(find.text('Von Erics Elf'), findsOneWidget);
    expect(find.textContaining('An '), findsNothing);
    // Die Marke bleibt erhalten, rückt aber in die zweite Zeile.
    expect(find.textContaining('Trade-Angebot'), findsOneWidget);
  });

  testWidgets('Selbst gestellt: die Karte nennt den Empfänger',
      (tester) async {
    await _zeige(tester, _karte('raus'));

    expect(find.text('An Erics Elf'), findsOneWidget);
    expect(find.textContaining('Von '), findsNothing);
  });

  testWidgets('Unbekannter Manager: kein geratener Name', (tester) async {
    // Die Liste kennt nur mich — der Handelspartner hat die Liga verlassen.
    await _zeige(
        tester,
        _karte('rein',
            manager: const [FantasyManager(userId: 'ich', username: 'SFV03')]));

    expect(find.text('Trade-Angebot'), findsOneWidget);
    expect(find.textContaining('Von '), findsNothing);
    expect(find.textContaining('An '), findsNothing);
  });
}
