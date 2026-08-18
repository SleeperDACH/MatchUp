import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/team_fixture.dart';
import '../features/favorites/favorites.dart';
import '../features/favorites/logic/next_favorite_fixtures.dart';

/// Die nächsten Spiele der favorisierten Vereine für den Homescreen.
///
/// Liest über `teamFixturesProvider` — denselben Weg wie der Favoriten-Tab.
/// Der erste Anlauf ging über die Saison-Spielpläne der Ligen, in denen die
/// Vereine favorisiert wurden: billiger, aber falsch. Pokalspiele stehen dort
/// nicht, und genau eines davon war das nächste Spiel (Verl – HSV im Pokal
/// vor dem ersten Spieltag). Zwei Ansichten, die dasselbe versprechen und
/// Verschiedenes zeigen, sind schlimmer als ein Abruf mehr.
///
/// Favorisierte **Ligen** bleiben außen vor — „nächstes Spiel" ist eine Frage
/// an einen Verein, nicht an einen Wettbewerb.
final favoritenSpieleProvider = FutureProvider<List<TeamFixture>>((ref) async {
  if (!AppConfig.isSupabaseConfigured) return const [];
  final teams = ref
      .watch(favoritesProvider)
      .where((f) => f.type == FavoriteType.team)
      .toList();
  if (teams.isEmpty) return const [];

  final alle = <TeamFixture>[];
  for (final t in teams) {
    try {
      // `teamIdOf`: der Favoriten-Schlüssel trägt das `sportmonks:`-Präfix,
      // der Spielplan-Endpunkt will die nackte ID.
      alle.addAll(
          await ref.watch(teamFixturesProvider(teamIdOf(t.key)).future));
    } catch (_) {
      continue; // Ein Verein ohne Spielplan darf die Zeile nicht leeren.
    }
  }
  return naechsteFavoritenSpiele(fixtures: alle, jetzt: DateTime.now());
});
