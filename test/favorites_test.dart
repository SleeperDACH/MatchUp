import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/favorites/favorites.dart';

TeamRef _t(String name, [String? short]) =>
    TeamRef(id: 'x', name: name, shortName: short ?? name);

void main() {
  group('isPlaceholderTeam', () {
    test('echte Teams sind keine Platzhalter', () {
      expect(isPlaceholderTeam(_t('Argentinien', 'ARG')), isFalse);
      expect(isPlaceholderTeam(_t('FC Bayern München', 'Bayern')), isFalse);
    });

    test('K.-o.-Platzhalter werden erkannt', () {
      expect(isPlaceholderTeam(_t('ARG/CPV', 'ARG/CPV')), isTrue);
      expect(isPlaceholderTeam(_t('CIV/NOR', 'CIV/NOR')), isTrue);
      expect(isPlaceholderTeam(_t('2H', '2H')), isTrue);
      expect(isPlaceholderTeam(_t('1A', '1A')), isTrue);
    });
  });

  group('isTeamFavorited', () {
    Favorite fav(String key) => Favorite(
        type: FavoriteType.team,
        key: key,
        label: 'Testverein',
        leagueId: 'bundesliga');

    test('erkennt den Favoriten am Schlüssel', () {
      expect(isTeamFavorited([fav('sportmonks:503')], 'sportmonks:503'),
          isTrue);
      expect(isTeamFavorited([fav('sportmonks:503')], 'sportmonks:504'),
          isFalse);
      expect(isTeamFavorited(const [], 'sportmonks:503'), isFalse);
    });

    test('abweichendes Präfix zählt als derselbe Verein', () {
      // Sonst leuchtet der Stern nicht und die alte Zeile bleibt für immer.
      expect(isTeamFavorited([fav('503')], 'sportmonks:503'), isTrue);
      expect(isTeamFavorited([fav('openligadb:503')], 'sportmonks:503'),
          isTrue);
    });

    test('nicht auflösbare Schlüssel gelten nicht als anzeigbar', () {
      expect(isResolvableTeamFavorite(fav('sportmonks:503')), isTrue);
      expect(isResolvableTeamFavorite(fav('openligadb:100')), isFalse);
      expect(isResolvableTeamFavorite(fav('100')), isFalse);
    });

    test('Ligen-Favoriten zählen nicht als Team', () {
      final liga = Favorite(
          type: FavoriteType.league, key: 'bundesliga', label: 'Bundesliga');
      expect(isTeamFavorited([liga], 'bundesliga'), isFalse);
    });
  });
}
