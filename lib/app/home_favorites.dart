import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/models/team_fixture.dart';
import '../features/tippspiel/providers.dart' show liveFixturesProvider;
import '../features/favorites/favorites.dart';
import '../features/favorites/logic/favorite_order.dart';
import '../features/favorites/logic/next_favorite_fixtures.dart';

/// Die Spiele der favorisierten Vereine in dieser Fußballwoche (Freitag bis
/// Montag 15:00) — für die Kopfkarte und den Abschnitt „Mein Wochenende".
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
  final tagesspiele = wochenendSpiele(
    fixtures: alle,
    jetzt: DateTime.now(),
  );

  // Vorn steht das Spiel des **obersten Favoriten**, nicht das früheste: Die
  // Kopfkarte des Homescreens nimmt sich den ersten Eintrag, der Abschnitt
  // „Mein Wochenende" den Rest. An einem Samstag mit vier Vereinen wäre sonst
  // der 13:30-Anstoß auf der Kopfkarte gelandet, egal wem er gehört.
  // **Der Live-Stand liegt über dem Spielplan** (17.10.2026, gemeldet: „das
  // Spiel oben in der Box wird nicht mehr als live angezeigt, obwohl es
  // läuft"). Der Vereinsspielplan wird einmal geladen; wer die App vor dem
  // Anpfiff öffnete, sah das Spiel bis zum nächsten Kaltstart als „geplant".
  // Jetzt dieselbe Bauart wie im Live-Tab: der eine Sammelabruf
  // (`liveFixturesProvider`) über die Partien gelegt, und ein Takt, der ihn
  // auffrischt — siehe [_planeLiveTakt].
  final live = ref.watch(liveFixturesProvider).valueOrNull ?? const {};
  final mitLive = [for (final f in tagesspiele) _mitLiveStand(f, live[f.id])];
  _planeLiveTakt(ref, mitLive);

  final raenge = favoritenRaenge(ref.watch(favoritesProvider));
  return favoritenSpielZuerst(
    spiele: mitLive,
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

/// Stand, Zustand und Anstoß aus dem Live-Abruf — alles andere (Wettbewerb,
/// Logo, Spieltag) bleibt, wie der Spielplan es kennt.
TeamFixture _mitLiveStand(TeamFixture f, Fixture? l) => l == null
    ? f
    : TeamFixture(
        id: f.id,
        kickoff: l.kickoff,
        status: l.status,
        leagueName: f.leagueName,
        leagueLogo: f.leagueLogo,
        round: f.round,
        home: f.home,
        away: f.away,
        homeScore: l.homeScore,
        awayScore: l.awayScore,
      );

/// **Wann der Live-Stand der Kopfkarte aufgefrischt wird.**
///
/// * Läuft ein Spiel (oder ist es angepfiffen und noch nicht beendet), alle
///   30 Sekunden — der Live-Tab nimmt 10, die Kopfkarte braucht weniger.
/// * Steht das nächste erst an, **ein** Wecker genau zum Anstoß.
/// * Sonst nichts — an einem spielfreien Mittwoch kostet die Karte keinen
///   Abruf.
///
/// Ein einmaliger `Timer` statt `Timer.periodic`: Die Auffrischung baut diesen
/// Provider neu, und der stellt dabei den nächsten Takt — dieselbe Bauart wie
/// beim Nachladen der Live-Punkte.
void _planeLiveTakt(Ref ref, List<TeamFixture> spiele) {
  final jetzt = DateTime.now();
  final laeuft = spiele.any((f) =>
      f.status == FixtureStatus.live ||
      (f.status == FixtureStatus.scheduled &&
          !f.kickoff.isAfter(jetzt) &&
          jetzt.difference(f.kickoff) < const Duration(hours: 3)));
  Duration? warte;
  if (laeuft) {
    warte = const Duration(seconds: 30);
  } else {
    final kommend = [
      for (final f in spiele)
        if (f.status == FixtureStatus.scheduled && f.kickoff.isAfter(jetzt))
          f.kickoff,
    ]..sort();
    if (kommend.isNotEmpty) {
      warte = kommend.first.difference(jetzt) + const Duration(seconds: 5);
    }
  }
  if (warte == null) return;
  final timer = Timer(warte, () => ref.invalidate(liveFixturesProvider));
  ref.onDispose(timer.cancel);
}
