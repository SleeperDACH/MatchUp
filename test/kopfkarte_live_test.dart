import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_favorites.dart';
import 'package:matchup/core/config/app_config.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:matchup/features/favorites/logic/next_favorite_fixtures.dart';
import 'package:matchup/features/tippspiel/providers.dart';

/// **Die Kopfkarte zeigt den Live-Stand** — gemeldet am 17.10.2026: „Das
/// Spiel oben in der Box wird nicht mehr als live angezeigt, obwohl es gerade
/// läuft."
///
/// Der Vereinsspielplan wird einmal geladen. Wer die App vor dem Anpfiff
/// öffnete, behielt den Stand von damals. Jetzt liegt der Live-Abruf darüber.
class _FesteFavoriten extends FavoritesNotifier {
  _FesteFavoriten(List<Favorite> favs) : super(null) {
    state = favs;
  }
}

void main() {
  test('ein laufendes Spiel steht als live da, mit Stand', () async {
    final vorher = AppConfig.supabaseInitialized;
    AppConfig.supabaseInitialized = true;
    addTearDown(() => AppConfig.supabaseInitialized = vorher);

    // Mitten in der Fußballwoche, damit die Partie im Fenster liegt — an
    // jedem Wochentag, an dem der Test läuft.
    final anpfiff = fussballWoche(DateTime.now()).von.add(const Duration(hours: 20));
    const hsv = TeamRef(id: 'sportmonks:2708', name: 'Hamburger SV', shortName: 'HSV');
    const fcu = TeamRef(id: 'sportmonks:1079', name: 'FC Union Berlin', shortName: 'FCU');

    // So stand es beim Öffnen der App: geplant, ohne Stand.
    final geplant = TeamFixture(
      id: 'sportmonks:19735147',
      kickoff: anpfiff,
      status: FixtureStatus.scheduled,
      leagueName: 'Bundesliga',
      home: hsv,
      away: fcu,
    );
    // Und so meldet es der Live-Abruf jetzt.
    final live = Fixture(
      id: 'sportmonks:19735147',
      leagueId: 'bundesliga',
      season: 2026,
      round: 7,
      roundName: '7. Spieltag',
      kickoff: anpfiff,
      home: hsv,
      away: fcu,
      status: FixtureStatus.live,
      homeScore: 1,
      awayScore: 0,
    );

    final c = ProviderContainer(overrides: [
      favoritesProvider.overrideWith((ref) => _FesteFavoriten(const [
            Favorite(
                type: FavoriteType.team,
                key: 'sportmonks:2708',
                label: 'Hamburger SV',
                leagueId: 'bundesliga'),
          ])),
      teamFixturesProvider.overrideWith((ref, id) async => [geplant]),
      liveFixturesProvider
          .overrideWith((ref) async => {live.id: live}),
    ]);
    addTearDown(c.dispose);

    await c.read(liveFixturesProvider.future);
    final sub = c.listen(favoritenSpieleProvider, (_, _) {});
    addTearDown(sub.close);
    final spiele = await c.read(favoritenSpieleProvider.future);

    expect(spiele, hasLength(1));
    expect(spiele.single.status, FixtureStatus.live);
    expect(spiele.single.homeScore, 1);
    expect(spiele.single.leagueName, 'Bundesliga',
        reason: 'was nur der Spielplan kennt, bleibt');
  });
}
