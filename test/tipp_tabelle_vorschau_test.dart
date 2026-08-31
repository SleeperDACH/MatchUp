import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/auth/providers.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';
import 'package:matchup/features/tippspiel/providers.dart';
import 'package:matchup/features/tippspiel/ui/tips_table_tab.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/schrift.dart';

/// Vorschau der **Tipp-Tabelle**.
///
/// Der Schirm hatte keine — und war damit der einzige große des Tippspiels,
/// über den sich nichts sagen ließ, ohne die App zu starten. Genau davor warnt
/// diese Datei an mehreren Stellen: Was keine Vorschau hat, sieht sich niemand
/// an.
TipRound _runde() => TipRound(
      id: 'r1',
      name: 'MatchUp! Tipprunde',
      leagueId: 'bundesliga',
      season: 2026,
      inviteCode: 'ABC123',
      scoring: ScoringRules.kicktippDefault,
      createdBy: 'ich',
    );

Fixture _fx(String id, String h, String a, {int? hs, int? as}) => Fixture(
      id: id,
      leagueId: 'bundesliga',
      season: 2026,
      round: 3,
      roundName: 'Spieltag 3',
      kickoff: DateTime(2026, 9, 12, 20, 30),
      home: TeamRef(id: h, name: h, shortName: h.substring(0, 3)),
      away: TeamRef(id: a, name: a, shortName: a.substring(0, 3)),
      homeScore: hs,
      awayScore: as,
      status: hs == null ? FixtureStatus.scheduled : FixtureStatus.finished,
    );

void main() {
  setUpAll(ladeSchrift);

  testWidgets('Vorschau: Tipp-Tabelle', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final runde = _runde();
    final spiele = [
      _fx('f1', 'Bayern', 'Dortmund', hs: 2, as: 1),
      _fx('f2', 'Leipzig', 'Union Berlin', hs: 0, as: 0),
      _fx('f3', 'Freiburg', 'Augsburg', hs: 3, as: 1),
      _fx('f4', 'Werder Bremen', 'Mainz'),
    ];
    const namen = [
      'SFV03',
      'JojoAcz44',
      'lennartruepke',
      'Spitzenreiter04',
      'ana',
      'Majusch',
    ];
    final mitglieder = [
      for (final (i, n) in namen.indexed)
        RoundMember(userId: 'm$i', username: n, avatarEmoji: '🙂'),
    ];
    // Tipps so gestreut, dass alle Zellzustände im Bild stehen: exakt,
    // Tordifferenz, Tendenz, daneben, offen.
    final tipps = <MemberTip>[
      for (final (i, _) in namen.indexed) ...[
        MemberTip(
            userId: 'm$i', fixtureId: 'f1', homeGoals: 2, awayGoals: i % 3),
        MemberTip(
            userId: 'm$i', fixtureId: 'f2', homeGoals: i % 2, awayGoals: 0),
        if (i != 2)
          MemberTip(
              userId: 'm$i', fixtureId: 'f3', homeGoals: 3 - (i % 2), awayGoals: 1),
        if (i < 4)
          MemberTip(userId: 'm$i', fixtureId: 'f4', homeGoals: 1, awayGoals: 1),
      ],
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWith((ref) => User(
                id: 'm0',
                appMetadata: const {},
                userMetadata: const {},
                aud: 'authenticated',
                createdAt: DateTime(2026).toIso8601String(),
              )),
          currentRoundProvider.overrideWith((ref) async => 3),
          selectedRoundProvider.overrideWith((ref) => 3),
          roundFixturesProvider.overrideWith((ref, r) async => spiele),
          leagueSeasonFixturesProvider.overrideWith((ref, id) async => spiele),
          roundMembersProvider.overrideWith((ref, id) async => mitglieder),
          allRoundTipsProvider.overrideWith((ref, id) async => tipps),
          frozenOddsProvider.overrideWith((ref) async => const {}),
          tipPresenceProvider.overrideWith((ref, id) async => const <String>{}),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: TipsTableTab(round: runde)),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    await expectLater(find.byType(TipsTableTab),
        matchesGoldenFile('goldens/tipp_tabelle_vorschau.png'));
  });
}
