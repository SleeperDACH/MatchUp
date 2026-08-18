import '../models/fantasy_models.dart';

/// Grundton eines Liga-Zustands — bestimmt die Farbe des Punkts davor.
enum LeagueStatusTone {
  /// Wartet auf etwas (Setup, noch nicht genug Teams).
  wartet,

  /// Läuft gerade und hat eine Uhr (Draft).
  laeuft,

  /// Erledigt/in Ordnung (Kader steht, Saison läuft).
  bereit,
}

/// Kurzer Zustandstext einer Fantasy-Liga für die Homescreen-Kachel.
/// Ohne ihn sehen alle Ligen gleich aus: vor dem ersten gewerteten Spieltag
/// zeigt [FantasyRankChip] bewusst nichts, und Name + Modus allein
/// unterscheiden zwei Redraft-Ligen nicht.
class LeagueStatus {
  const LeagueStatus(this.label, {this.detail, required this.tone});

  /// Erste, kräftige Zeile („Draft läuft").
  final String label;

  /// Zweite, leise Zeile („Pick 14", „3/10 Teams").
  final String? detail;

  final LeagueStatusTone tone;
}

/// Zustand aus dem, was die Liga selbst mitbringt. [teams] ist die Zahl der
/// Manager (aus `fantasyManagersProvider`); `null`, solange sie lädt.
LeagueStatus fantasyStatus(FantasyLeague league, {int? teams}) {
  final platz = switch ((teams, league.maxTeams)) {
    (final t?, final max?) => '$t/$max Teams',
    (final t?, null) => t == 1 ? '1 Team' : '$t Teams',
    _ => null,
  };
  return switch (league.draftStatus) {
    // Kurze Wörter: auf der schmalen Karte (vier nebeneinander) ist für
    // ganze Sätze kein Platz, und ein abgeschnittenes „Wartet a…" sagt
    // weniger als ein vollständiges Wort.
    DraftStatus.setup => LeagueStatus(
        teams != null && league.maxTeams != null && teams < league.maxTeams!
            ? 'Offen'
            : 'Startklar',
        detail: platz,
        tone: LeagueStatusTone.wartet,
      ),
    DraftStatus.drafting => LeagueStatus(
        'Draft läuft',
        // Pick-Nummer 1-basiert: `picksMade` zählt die fertigen Picks.
        detail: 'Pick ${league.picksMade + 1}',
        tone: LeagueStatusTone.laeuft,
      ),
    DraftStatus.done => LeagueStatus(
        'Kader steht',
        detail: platz,
        tone: LeagueStatusTone.bereit,
      ),
  };
}
