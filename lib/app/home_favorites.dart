import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/team_fixture.dart';
import '../features/favorites/favorites.dart';
import '../features/favorites/logic/favorite_order.dart';
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
  // `isResolvableTeamFavorite`: ein Schlüssel aus einer früheren Quelle
  // (`openligadb:100`) wird zu `100` gekürzt — und diese ID gibt es bei
  // Sportmonks, nur gehört sie einem **fremden** Verein. Ungefiltert stand
  // hier das Spiel eines Vereins, den nie jemand favorisiert hat.
  final teams = ref
      .watch(favoritesProvider)
      .where((f) => f.type == FavoriteType.team && isResolvableTeamFavorite(f))
      .toList();
  if (teams.isEmpty) return const [];

  final alle = <TeamFixture>[];
  for (final t in teams) {
    try {
      // `teamIdOf`: der Favoriten-Schlüssel trägt das `sportmonks:`-Präfix,
      // der Spielplan-Endpunkt will die nackte ID.
      alle.addAll(
        await ref.watch(teamFixturesProvider(teamIdOf(t.key)).future),
      );
    } catch (_) {
      continue; // Ein Verein ohne Spielplan darf die Zeile nicht leeren.
    }
  }
  final tagesspiele = naechsteFavoritenSpiele(
    fixtures: alle,
    jetzt: DateTime.now(),
  );

  // Vorn steht das Spiel des **obersten Favoriten**, nicht das früheste: Die
  // Kopfkarte des Homescreens nimmt sich den ersten Eintrag, der Abschnitt
  // „Meine Vereine" den Rest. An einem Samstag mit vier Vereinen wäre sonst
  // der 13:30-Anstoß auf der Kopfkarte gelandet, egal wem er gehört.
  final raenge = favoritenRaenge(ref.watch(favoritesProvider));
  return favoritenSpielZuerst(
    spiele: tagesspiele,
    rang: (f) {
      final h = raenge[teamIdOf(f.home.id)];
      final a = raenge[teamIdOf(f.away.id)];
      if (h == null) return a;
      if (a == null) return h;
      // Favorit gegen Favorit: der höher stehende bestimmt den Rang.
      return h < a ? h : a;
    },
  );
});
