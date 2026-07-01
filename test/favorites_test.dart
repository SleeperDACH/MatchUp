import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/favorites/favorites.dart';

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
}
