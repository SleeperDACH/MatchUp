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
    this.sportmonksKey,
    this.fixedSeason,
    this.oddsSportKey,
  });

  /// App-interne, stabile ID, z. B. `bundesliga`.
  final String id;
  final Sport sport;
  final String name;

  /// Bezeichnung einer Runde in dieser Liga: "Spieltag", "Week", …
  final String roundLabel;

  /// Welcher Daten-Adapter diese Liga bedient (z. B. `openligadb`).
  final String providerId;

  /// Schlüssel der Liga beim primären Provider (z. B. `bl1` bei OpenLigaDB).
  /// Bleibt bei Sportmonks-Ligen der OpenLigaDB-Kürzel — Fantasy, Tippspiel
  /// und der `sync-fixtures`-Job nutzen ihn weiter.
  final String providerLeagueKey;

  /// Sportmonks-League-ID (falls diese Liga über Sportmonks läuft). Getrennt
  /// von [providerLeagueKey], damit Fantasy/Tipp parallel auf OpenLigaDB
  /// bleiben können.
  final String? sportmonksKey;

  /// Für Turniere (WM, EM): festes Jahr statt rollierender Saison.
  final int? fixedSeason;

  /// Sport-Key bei der Quoten-Quelle (The Odds API), z. B.
  /// `soccer_germany_bundesliga`. `null` = keine Wettquoten für diese Liga.
  final String? oddsSportKey;

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

  /// Ein (vorläufiger) Spielstand liegt vor — live oder endgültig.
  /// Grundlage für die Live-Wertung in der Tabelle.
  bool get hasScore => homeScore != null && awayScore != null;
}

/// Eine Zeile der Liga-/Gruppentabelle.
class StandingRow {
  const StandingRow({
    required this.rank,
    required this.team,
    required this.points,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
  });

  final int rank;
  final TeamRef team;
  final int points;
  final int played;
  final int won;
  final int draw;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;

  int get goalDiff => goalsFor - goalsAgainst;
}

/// Vorkonfigurierte Wettbewerbe. Hier kommen später Premier League,
/// NFL & Co. dazu.
abstract final class Leagues {
  // Die fünf deutschen Ligen laufen über Sportmonks (providerId `sportmonks`,
  // [sportmonksKey] = Sportmonks-League-ID). [providerLeagueKey] bleibt der
  // OpenLigaDB-Kürzel, damit Fantasy, Tippspiel und `sync-fixtures` weiter
  // gegen OpenLigaDB arbeiten (getrennte Pipeline).
  static const bundesliga = LeagueInfo(
    id: 'bundesliga',
    sport: Sport.football,
    name: 'Bundesliga',
    roundLabel: 'Spieltag',
    providerId: 'sportmonks',
    providerLeagueKey: 'bl1',
    sportmonksKey: '82',
    oddsSportKey: 'soccer_germany_bundesliga',
  );

  static const bundesliga2 = LeagueInfo(
    id: 'bundesliga2',
    sport: Sport.football,
    name: '2. Bundesliga',
    roundLabel: 'Spieltag',
    providerId: 'sportmonks',
    providerLeagueKey: 'bl2',
    sportmonksKey: '85',
    oddsSportKey: 'soccer_germany_bundesliga2',
  );

  static const liga3 = LeagueInfo(
    id: 'liga3',
    sport: Sport.football,
    name: '3. Liga',
    roundLabel: 'Spieltag',
    providerId: 'sportmonks',
    providerLeagueKey: 'bl3',
    sportmonksKey: '88',
  );

  static const dfbPokal = LeagueInfo(
    id: 'dfb_pokal',
    sport: Sport.football,
    name: 'DFB-Pokal',
    roundLabel: 'Runde',
    providerId: 'sportmonks',
    providerLeagueKey: 'dfb',
    sportmonksKey: '109',
  );

  static const frauenBundesliga = LeagueInfo(
    id: 'frauen_bundesliga',
    sport: Sport.football,
    name: 'Frauen-Bundesliga',
    roundLabel: 'Spieltag',
    providerId: 'sportmonks',
    providerLeagueKey: 'fbl1',
    sportmonksKey: '1740',
  );

  static const all = [
    bundesliga,
    bundesliga2,
    liga3,
    dfbPokal,
    frauenBundesliga,
  ];

  /// Wettbewerbe, die für **Tippspiele** wählbar sind (1./2. Bundesliga +
  /// DFB-Pokal). Mehrere davon lassen sich in einer Tipprunde kombinieren.
  /// Fantasy bleibt bewusst auf die 1. Bundesliga beschränkt.
  static const tippspiel = [bundesliga, bundesliga2, dfbPokal];

  static LeagueInfo byId(String id) =>
      all.firstWhere((l) => l.id == id, orElse: () => bundesliga);

  /// Liga zur Sportmonks-League-ID (z. B. „82" → Bundesliga); null wenn unbekannt.
  static LeagueInfo? bySportmonksKey(String? key) {
    if (key == null) return null;
    for (final l in all) {
      if (l.sportmonksKey == key) return l;
    }
    return null;
  }
}
