import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/app/theme.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/favorites/ui/favorites_tab.dart';
import 'package:matchup/features/news/models/news_item.dart';
import 'package:matchup/features/news/providers.dart';
import 'package:matchup/features/tippspiel/providers.dart';

import 'support/schrift.dart';

/// Vorschau des **Favoriten-Tabs** — kein Regressionstest:
///   flutter test --update-goldens test/favoriten_vorschau_test.dart
///   -> test/goldens/favoriten_vorschau.png
///
/// Wie bei Homescreen und Live-Tab: Auf dem Gerät zeigt der Schirm nur, was
/// der eigene Account gerade hergibt. Hier stehen vier Favoriten mit
/// Spielplan fest im Test, damit sich der Aufbau überhaupt beurteilen lässt.
///
/// Der Bildvergleich läuft nur mit `--update-goldens` — die Spiele liegen
/// relativ zu heute, das Bild trüge sonst jeden Tag ein anderes Datum und der
/// Test wäre täglich rot.

/// Favoriten mit vorgegebenem Stand, ohne Server.
class _FesteFavoriten extends FavoritesNotifier {
  _FesteFavoriten(List<Favorite> favs) : super(null) {
    state = favs;
  }
}

Favorite _fav(String id, String label, String kurz, String liga) => Favorite(
  type: FavoriteType.team,
  key: 'sportmonks:$id',
  label: label,
  shortName: kurz,
  leagueId: liga,
);

TeamFixture _fx(
  String id,
  String heim,
  String ausw,
  DateTime anstoss, {
  FixtureStatus status = FixtureStatus.scheduled,
  int? hs,
  int? as,
  String liga = 'Bundesliga',
  int runde = 3,
}) => TeamFixture(
  id: id,
  kickoff: anstoss,
  status: status,
  leagueName: liga,
  round: runde,
  home: TeamRef(id: 'h$id', name: heim, shortName: heim),
  away: TeamRef(id: 'a$id', name: ausw, shortName: ausw),
  homeScore: hs,
  awayScore: as,
);

void main() {
  setUpAll(() async {
    await ladeSchrift();
    await initializeDateFormatting('de_DE');
  });

  testWidgets('Vorschau: Favoriten-Tab', (tester) async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final n = DateTime.now();
    DateTime tag(int plus, int h, int m) =>
        DateTime(n.year, n.month, n.day + plus, h, m);

    final favs = [
      _fav('503', 'FC Bayern München', 'FCB', 'bundesliga'),
      _fav('2708', 'Hamburger SV', 'HSV', 'bundesliga'),
      _fav('68', 'Borussia Dortmund', 'BVB', 'bundesliga'),
      _fav('277', 'RB Leipzig', 'RBL', 'bundesliga'),
    ];

    final bayern = [
      _fx('1', 'FC Bayern München', 'VfB Stuttgart', tag(1, 20, 30)),
      _fx('2', 'SC Freiburg', 'FC Bayern München', tag(8, 15, 30)),
      _fx(
        '3',
        'FC Bayern München',
        '1. FC Köln',
        tag(-6, 18, 30),
        status: FixtureStatus.finished,
        hs: 3,
        as: 1,
        runde: 2,
      ),
      _fx(
        '4',
        'Eintracht Frankfurt',
        'FC Bayern München',
        tag(-13, 15, 30),
        status: FixtureStatus.finished,
        hs: 0,
        as: 2,
        runde: 1,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoritesProvider.overrideWith((ref) => _FesteFavoriten(favs)),
          teamFixturesProvider.overrideWith(
            (ref, id) async => id == '503' ? bayern : const <TeamFixture>[],
          ),
          teamNewsProvider.overrideWith((ref, args) async => const <NewsItem>[]),
          // Der Vereinskopf zeigt den Tabellenplatz — über die Team-ID, nicht
          // über den Namen.
          leagueTableProvider.overrideWith(
            (ref, id) async => [
              StandingRow(
                rank: 1,
                team: const TeamRef(
                  id: 'sportmonks:503',
                  name: 'FC Bayern München',
                  shortName: 'FCB',
                ),
                points: 9,
                played: 3,
                won: 3,
                draw: 0,
                lost: 0,
                goalsFor: 8,
                goalsAgainst: 2,
              ),
            ],
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(body: FavoritesTab()),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    if (!autoUpdateGoldenFiles) return;
    await expectLater(
      find.byType(FavoritesTab),
      matchesGoldenFile('goldens/favoriten_vorschau.png'),
    );
  });
}
