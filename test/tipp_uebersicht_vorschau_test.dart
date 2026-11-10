import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:matchup/features/tippspiel/ui/tipp_uebersicht_tab.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Übersicht einer Tipprunde (09.11.2026, Redesign „Richtung B").
/// Die Spiele liegen relativ zu jetzt, weil die Übersicht mit der echten Uhr
/// rechnet — das Bild ist deshalb eine Vorschau, kein harter Vergleich.
void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Tippspiel-Übersicht', (tester) async {
    await initializeDateFormatting('de_DE');
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final jetzt = DateTime.now();
    final morgen = DateTime(jetzt.year, jetzt.month, jetzt.day + 1, 15, 30);
    Fixture fx(String id, DateTime k, {int? h, int? a}) => Fixture(
          id: id,
          leagueId: 'bundesliga',
          season: 2026,
          round: 10,
          roundName: '10. Spieltag',
          kickoff: k,
          home: TeamRef(id: 'h$id', name: 'Heim $id', shortName: 'H'),
          away: TeamRef(id: 'g$id', name: 'Gast $id', shortName: 'G'),
          status:
              h == null ? FixtureStatus.scheduled : FixtureStatus.finished,
          homeScore: h,
          awayScore: a,
        );
    final spiele = [
      fx('a', jetzt.subtract(const Duration(days: 8)), h: 2, a: 1),
      fx('b', jetzt.subtract(const Duration(days: 8)), h: 0, a: 0),
      for (var i = 0; i < 5; i++)
        fx('n$i', morgen.add(Duration(hours: i))),
    ];
    const namen = ['ana', 'SFV03', 'JojoAcz44', 'Spitzenreiter04', 'Majusch'];
    final mitglieder = [
      for (final (i, n) in namen.indexed)
        RoundMember(userId: 'm$i', username: n),
    ];
    final tipps = [
      const MemberTip(userId: 'm0', fixtureId: 'a', homeGoals: 2, awayGoals: 1),
      const MemberTip(userId: 'm0', fixtureId: 'b', homeGoals: 0, awayGoals: 0),
      const MemberTip(userId: 'm1', fixtureId: 'a', homeGoals: 1, awayGoals: 0),
      const MemberTip(userId: 'm1', fixtureId: 'b', homeGoals: 1, awayGoals: 1),
      const MemberTip(userId: 'm2', fixtureId: 'a', homeGoals: 3, awayGoals: 1),
      const MemberTip(userId: 'm1', fixtureId: 'n0', homeGoals: 2, awayGoals: 0),
      const MemberTip(userId: 'm1', fixtureId: 'n1', homeGoals: 1, awayGoals: 1),
    ];
    const runde = TipRound(
      id: 'r1',
      name: 'BuLi 26/27',
      leagueId: 'bundesliga',
      season: 2026,
      inviteCode: 'ABC123',
      scoring: ScoringRules.kicktippDefault,
      createdBy: 'm1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'm1',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          leagueSeasonFixturesProvider.overrideWith((ref, id) async => spiele),
          roundMembersProvider.overrideWith((ref, id) async => mitglieder),
          allRoundTipsProvider.overrideWith((ref, id) async => tipps),
          frozenOddsProvider.overrideWith((ref) async => const {}),
          unreadChatProvider.overrideWith((ref, id) => true),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const DefaultTabController(
            length: 3,
            child: Scaffold(body: TippUebersichtTab(round: runde)),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('3 Tipps offen'), findsOneWidget);
    expect(find.textContaining('2 von 5 getippt'), findsOneWidget);
    expect(find.text('Jetzt tippen'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget, reason: 'ana 4+4, ich 3+?');
    expect(find.text('Liga-Chat'), findsOneWidget);
    expect(find.text('Neue Nachrichten'), findsOneWidget);
    expect(find.text('Spieler einladen'), findsNothing,
        reason: 'Einladen steht im Zahnrad, nicht in der Übersicht');

    // Hängt am Wochentag (die Spiele liegen relativ zu jetzt): nur Vorschau.
    if (!autoUpdateGoldenFiles) return;
    await expectLater(find.byType(TippUebersichtTab),
        matchesGoldenFile('goldens/tipp_uebersicht.png'));
  });
}
