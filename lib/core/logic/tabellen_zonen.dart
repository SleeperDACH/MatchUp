/// **Was ein Tabellenplatz bedeutet** (19.10.2026, auf Ansage): Meister,
/// Champions League, Europa League, Conference League, Relegation, Abstieg —
/// die europäischen Plätze nur in der Bundesliga, in der 2. und 3. Liga
/// Aufstieg, Relegation und Abstieg.
///
/// **Die Regelplätze, nicht der Einzelfall.** Gewinnt der Siebte den
/// DFB-Pokal, rückt er in die Europa League — das hängt am Pokal und an der
/// UEFA-Wertung und steht nirgends in unseren Daten. Gezeigt wird deshalb die
/// gewöhnliche Verteilung; die Abstiegsplätze zählen vom Tabellenende, damit
/// eine Liga mit 20 Vereinen (3. Liga) dieselbe Regel nutzt.
library;

import 'dart:ui' show Color;

enum TabellenZone {
  meister('Meister', Color(0xFFFFC83D)),
  championsLeague('Champions League', Color(0xFF3B82F6)),
  europaLeague('Europa League', Color(0xFFF97316)),
  conferenceLeague('Conference League', Color(0xFF14B8A6)),
  // Gold wie der Meister der Bundesliga (19.10.2026, auf Ansage): In der 2.
  // und 3. Liga ist der Aufstieg das, was dort der Titel ist.
  aufstieg('Aufstieg', Color(0xFFFFC83D)),
  relegation('Relegation', Color(0xFFA78BFA)),
  abstieg('Abstieg', Color(0xFFF23030));

  const TabellenZone(this.name, this.farbe);
  final String name;
  final Color farbe;
}

/// Die Zone des Platzes [rang] in einer Liga mit [teams] Vereinen, oder
/// `null` (Mittelfeld, unbekannte Liga, Turnier).
TabellenZone? tabellenZone(String? leagueId, int rang, int teams) {
  if (leagueId == null || rang < 1 || teams < 6) return null;
  final vonUnten = teams - rang; // 0 = Letzter
  switch (leagueId) {
    case 'bundesliga':
      if (rang == 1) return TabellenZone.meister;
      if (rang <= 4) return TabellenZone.championsLeague;
      if (rang == 5) return TabellenZone.europaLeague;
      if (rang == 6) return TabellenZone.conferenceLeague;
      if (vonUnten <= 1) return TabellenZone.abstieg;
      if (vonUnten == 2) return TabellenZone.relegation;
      return null;
    case 'bundesliga2':
      // Kein eigener Meister-Strich: Platz 1 und 2 steigen beide auf.
      if (rang <= 2) return TabellenZone.aufstieg;
      if (rang == 3) return TabellenZone.relegation;
      if (vonUnten <= 1) return TabellenZone.abstieg;
      if (vonUnten == 2) return TabellenZone.relegation;
      return null;
    case 'liga3':
      // Zwei steigen direkt auf, der Dritte spielt Relegation, vier steigen
      // ab (bei 20 Vereinen die Plätze 17 bis 20).
      if (rang <= 2) return TabellenZone.aufstieg;
      if (rang == 3) return TabellenZone.relegation;
      if (vonUnten <= 3) return TabellenZone.abstieg;
      return null;
  }
  return null;
}

/// Welche Zonen in dieser Liga vorkommen, in Tabellenreihenfolge — für die
/// Legende unter der Tabelle.
List<TabellenZone> zonenDerLiga(String? leagueId, int teams) {
  final gesehen = <TabellenZone>[];
  for (var r = 1; r <= teams; r++) {
    final z = tabellenZone(leagueId, r, teams);
    if (z != null && !gesehen.contains(z)) gesehen.add(z);
  }
  return gesehen;
}
