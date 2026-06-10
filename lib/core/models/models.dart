/// Sport-agnostische Domainmodelle.
///
/// Der Kern der App kennt keine Bundesliga: Er kennt Sportarten, Ligen,
/// Runden (Spieltag / Week / Game Day) und Fixtures (Spiele). Neue Ligen
/// oder Sportarten (Premier League, NFL, NBA) brauchen nur einen neuen
/// [LeagueInfo]-Eintrag und einen passenden Daten-Adapter.
library;

enum Sport { football, americanFootball, basketball }

class LeagueInfo {
  const LeagueInfo({
    required this.id,
    required this.sport,
    required this.name,
    required this.roundLabel,
    required this.providerId,
    required this.providerLeagueKey,
    this.fixedSeason,
  });

  /// App-interne, stabile ID, z. B. `bundesliga`.
  final String id;
  final Sport sport;
  final String name;

  /// Bezeichnung einer Runde in dieser Liga: "Spieltag", "Week", …
  final String roundLabel;

  /// Welcher Daten-Adapter diese Liga bedient (z. B. `openligadb`).
  final String providerId;

  /// Schlüssel der Liga beim Provider (z. B. `bl1` bei OpenLigaDB).
  final String providerLeagueKey;

  /// Für Turniere (WM, EM): festes Jahr statt rollierender Saison.
  final int? fixedSeason;

  /// Saison-Startjahr zu einem Zeitpunkt: Turniere haben ein festes Jahr,
  /// Vereinsligen wechseln im Juli (Saison 2025/26 → 2025).
  int seasonFor(DateTime now) =>
      fixedSeason ?? (now.month >= 7 ? now.year : now.year - 1);
}

/// Eine Runde im Spielplan (Spieltag, Gruppenphase, Achtelfinale, …).
class RoundInfo {
  const RoundInfo({required this.number, required this.name});

  final int number;
  final String name;
}

class TeamRef {
  const TeamRef({
    required this.id,
    required this.name,
    required this.shortName,
    this.iconUrl,
  });

  final String id;
  final String name;
  final String shortName;
  final String? iconUrl;
}

enum FixtureStatus { scheduled, live, finished }

class Fixture {
  const Fixture({
    required this.id,
    required this.leagueId,
    required this.season,
    required this.round,
    required this.roundName,
    required this.kickoff,
    required this.home,
    required this.away,
    required this.status,
    this.homeScore,
    this.awayScore,
  });

  /// Provider-übergreifend eindeutig: `<providerId>:<externeId>`.
  final String id;
  final String leagueId;

  /// Startjahr der Saison, z. B. 2025 für 2025/26.
  final int season;
  final int round;
  final String roundName;
  final DateTime kickoff;
  final TeamRef home;
  final TeamRef away;
  final FixtureStatus status;
  final int? homeScore;
  final int? awayScore;

  bool get hasStarted => DateTime.now().toUtc().isAfter(kickoff.toUtc());

  bool get hasResult =>
      status == FixtureStatus.finished && homeScore != null && awayScore != null;
}

/// Vorkonfigurierte Wettbewerbe. Hier kommen später Premier League,
/// NFL & Co. dazu.
abstract final class Leagues {
  static const bundesliga = LeagueInfo(
    id: 'bundesliga',
    sport: Sport.football,
    name: 'Bundesliga',
    roundLabel: 'Spieltag',
    providerId: 'openligadb',
    providerLeagueKey: 'bl1',
  );

  static const wm2026 = LeagueInfo(
    id: 'wm2026',
    sport: Sport.football,
    name: 'WM 2026',
    roundLabel: 'Runde',
    providerId: 'openligadb',
    providerLeagueKey: 'wm26',
    fixedSeason: 2026,
  );

  static const all = [wm2026, bundesliga];

  static LeagueInfo byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => bundesliga);
}
