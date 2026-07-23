/// Playoff-**Placement-Bracket** für Fantasy — pure Dart, ohne Abhängigkeiten
/// (analog zur Scoring-Engine getestet).
///
/// Aus der Endtabelle der regulären Saison (Setzung) entstehen zwei K.o.-Bäume,
/// die **parallel** über dieselben Playoff-Spieltage laufen:
///
/// * **Winner-Bracket** — die besten `playoffTeams` Setzungen spielen die
///   Plätze 1 … `playoffTeams` aus (Finale + Platzierungsspiele).
/// * **Loser-Bracket** — alle übrigen Teams spielen die restlichen
///   Abschlussplätze `playoffTeams+1` … N aus.
///
/// Beide sind **Placement-Brackets**: niemand scheidet aus, Sieger steigen in
/// den oberen, Verlierer in den unteren Zweig — am Ende hat **jedes Team eine
/// exakte Endplatzierung**. Nicht-Zweierpotenzen werden mit Freilosen (Byes)
/// für die Topgesetzten aufgefüllt.
library;

/// Ein Team-Platz in einer Bracket-Partie.
///
/// * `managerId != null` → gesetztes Team (mit Gesamt-Setzung [seed]).
/// * `bye == true` → Freilos-Platzhalter (struktureller Auffüller, zählt nicht).
/// * sonst → noch nicht ermittelt (TBD; Vorrunde noch offen).
class BracketSlot {
  const BracketSlot({this.managerId, this.seed, this.bye = false});

  final String? managerId;
  final int? seed;
  final bool bye;

  bool get isBye => bye;
  bool get isTbd => managerId == null && !bye;
}

/// Eine Bracket-Partie über [weeks] Spieltage ab [startMatchday].
class BracketMatch {
  const BracketMatch({
    required this.round,
    required this.label,
    required this.home,
    required this.away,
    required this.homePoints,
    required this.awayPoints,
    required this.decided,
    required this.winnerId,
    required this.startMatchday,
    required this.weeks,
  });

  /// 0-basierter Rundenindex innerhalb des Playoff-Fensters.
  final int round;

  /// Sprechendes Label des ausgespielten Platzes, z. B. „Finale",
  /// „Spiel um Platz 3", „Halbfinale".
  final String label;

  final BracketSlot home;
  final BracketSlot away;
  final int homePoints;
  final int awayPoints;

  /// Alle Spieltage der Partie sind beendet → Ergebnis steht.
  final bool decided;
  final String? winnerId;

  final int startMatchday;
  final int weeks;

  bool get isLive => !decided && (homePoints > 0 || awayPoints > 0);
}

/// Eine Runde (ein Zeitfenster) eines Brackets.
class BracketRound {
  const BracketRound({
    required this.index,
    required this.startMatchday,
    required this.matches,
  });

  final int index;
  final int startMatchday;
  final List<BracketMatch> matches;
}

/// Endplatzierung eines Teams (nur belegt, wenn die entscheidende Partie
/// beendet ist).
class BracketPlacement {
  const BracketPlacement({required this.place, required this.managerId});

  final int place;
  final String? managerId;

  bool get decided => managerId != null;
}

/// Vollständiges Playoff-Ergebnis: beide Brackets + gemeinsame Endtabelle.
class PlayoffBracket {
  const PlayoffBracket({
    required this.winners,
    required this.consolation,
    required this.placements,
    required this.playoffTeams,
    required this.startRound,
    required this.weeksPerRound,
  });

  /// Winner-Bracket (Plätze 1 … [playoffTeams]).
  final List<BracketRound> winners;

  /// Loser-/Trost-Bracket (Plätze [playoffTeams]+1 … N).
  final List<BracketRound> consolation;

  /// Exakte Endplatzierung 1 … N (undecided → managerId null).
  final List<BracketPlacement> placements;

  final int playoffTeams;
  final int startRound;
  final int weeksPerRound;

  /// Alle Plätze ausgespielt.
  bool get complete => placements.every((p) => p.decided);
}

/// Baut das komplette Playoff-Bracket aus der Setzung [seeding] (beste Setzung
/// zuerst, üblich: Endtabelle der regulären Saison).
///
/// [roundTotals] bildet Spieltag → (managerId → Punkte) ab (nur vorhandene/
/// gewertete Spieltage). [finishedMatchdays] enthält die Spieltage, deren
/// Spiele **abgeschlossen** sind — nur dann gilt eine Partie als entschieden.
PlayoffBracket buildPlayoffBracket({
  required List<String> seeding,
  required int playoffTeams,
  required int startRound,
  required int weeksPerRound,
  required Map<int, Map<String, int>> roundTotals,
  required Set<int> finishedMatchdays,
}) {
  final n = seeding.length;
  final pt = playoffTeams.clamp(0, n);

  // Punkte eines Teams in Playoff-Runde [r] (Summe über die Runden-Spieltage).
  int roundPoints(String id, int r) {
    final md0 = startRound + r * weeksPerRound;
    var sum = 0;
    for (var w = 0; w < weeksPerRound; w++) {
      sum += roundTotals[md0 + w]?[id] ?? 0;
    }
    return sum;
  }

  bool roundFinished(int r) {
    final md0 = startRound + r * weeksPerRound;
    for (var w = 0; w < weeksPerRound; w++) {
      if (!finishedMatchdays.contains(md0 + w)) return false;
    }
    return true;
  }

  final byRound = <int, List<BracketMatch>>{};

  String roundName(int size) => switch (size) {
        2 => 'Finale',
        4 => 'Halbfinale',
        8 => 'Viertelfinale',
        16 => 'Achtelfinale',
        _ => 'Runde',
      };

  // Label einer Partie, die im Teilbaum der Plätze [placeLo … placeLo+size-1]
  // liegt. Das Blatt (size 2) benennt den konkreten Platz.
  String labelFor(int size, int placeLo) {
    if (size == 2) {
      return placeLo == 1 ? 'Finale' : 'Spiel um Platz $placeLo';
    }
    final name = roundName(size);
    return placeLo == 1 ? name : '$name · Plätze $placeLo–${placeLo + size - 1}';
  }

  /// Rekursives Placement: [entrants] (nach Setzung geordnet, ggf. mit Byes)
  /// spielen die Plätze [placeLo … placeLo+entrants.length-1] aus. Sieger in den
  /// oberen, Verlierer in den unteren Halbbaum. Liefert die Teilnehmer in
  /// Endplatz-Reihenfolge (undecided/bye bleiben als Platzhalter erhalten).
  List<BracketSlot> place(List<BracketSlot> entrants, int roundIndex, int placeLo) {
    final m = entrants.length;
    if (m <= 1) return entrants;

    final startMd = startRound + roundIndex * weeksPerRound;
    final winners = <BracketSlot>[];
    final losers = <BracketSlot>[];

    for (var i = 0; i < m ~/ 2; i++) {
      final home = entrants[i]; // höhere Setzung
      final away = entrants[m - 1 - i]; // niedrigere Setzung

      // Freilos: das reale Team steigt ohne Partie auf.
      if (home.isBye || away.isBye) {
        if (away.isBye) {
          winners.add(home);
          losers.add(away);
        } else {
          winners.add(away);
          losers.add(home);
        }
        continue;
      }

      // Vorrunde noch offen → Partie steht noch nicht.
      if (home.isTbd || away.isTbd) {
        (byRound[roundIndex] ??= []).add(BracketMatch(
          round: roundIndex,
          label: labelFor(m, placeLo),
          home: home,
          away: away,
          homePoints: 0,
          awayPoints: 0,
          decided: false,
          winnerId: null,
          startMatchday: startMd,
          weeks: weeksPerRound,
        ));
        winners.add(const BracketSlot());
        losers.add(const BracketSlot());
        continue;
      }

      final hp = roundPoints(home.managerId!, roundIndex);
      final ap = roundPoints(away.managerId!, roundIndex);
      final decided = roundFinished(roundIndex);
      // Gleichstand: die höhere Setzung (home) kommt weiter.
      final homeWins = hp >= ap;
      final winner = decided ? (homeWins ? home : away) : const BracketSlot();
      final loser = decided ? (homeWins ? away : home) : const BracketSlot();

      (byRound[roundIndex] ??= []).add(BracketMatch(
        round: roundIndex,
        label: labelFor(m, placeLo),
        home: home,
        away: away,
        homePoints: hp,
        awayPoints: ap,
        decided: decided,
        winnerId: decided ? winner.managerId : null,
        startMatchday: startMd,
        weeks: weeksPerRound,
      ));
      winners.add(winner);
      losers.add(loser);
    }

    final upper = place(winners, roundIndex + 1, placeLo);
    final lower = place(losers, roundIndex + 1, placeLo + m ~/ 2);
    return [...upper, ...lower];
  }

  // Teilnehmer eines Setzungs-Blocks zu Slots (mit Gesamt-Setzung) + Byes bis
  // zur nächsten Zweierpotenz auffüllen (Byes hinten → treffen die Topgesetzten).
  List<BracketSlot> entrantsFor(int from, int to) {
    final slots = <BracketSlot>[
      for (var i = from; i < to; i++)
        BracketSlot(managerId: seeding[i], seed: i + 1),
    ];
    var p = 1;
    while (p < slots.length) {
      p *= 2;
    }
    while (slots.length < p) {
      slots.add(const BracketSlot(bye: true));
    }
    return slots;
  }

  List<BracketRound> roundsFrom(Map<int, List<BracketMatch>> map) {
    final indices = map.keys.toList()..sort();
    return [
      for (final i in indices)
        BracketRound(
          index: i,
          startMatchday: startRound + i * weeksPerRound,
          matches: map[i]!,
        ),
    ];
  }

  // Winner-Bracket.
  final winnerMap = <int, List<BracketMatch>>{};
  var winnerOrder = <BracketSlot>[];
  if (pt >= 2) {
    // place() schreibt in `byRound`; wir isolieren die Winner-Partien.
    byRound.clear();
    winnerOrder = place(entrantsFor(0, pt), 0, 1);
    winnerMap.addAll(byRound);
  } else {
    winnerOrder = [for (var i = 0; i < pt; i++) BracketSlot(managerId: seeding[i], seed: i + 1)];
  }

  // Loser-/Trost-Bracket.
  final consoMap = <int, List<BracketMatch>>{};
  var consoOrder = <BracketSlot>[];
  if (n - pt >= 2) {
    byRound.clear();
    consoOrder = place(entrantsFor(pt, n), 0, pt + 1);
    consoMap.addAll(byRound);
  } else {
    consoOrder = [for (var i = pt; i < n; i++) BracketSlot(managerId: seeding[i], seed: i + 1)];
  }

  // Endtabelle: reale Slots in Platz-Reihenfolge (Byes verworfen).
  final ordered = <BracketSlot>[
    for (final s in winnerOrder)
      if (!s.isBye) s,
    for (final s in consoOrder)
      if (!s.isBye) s,
  ];
  final placements = <BracketPlacement>[
    for (var i = 0; i < ordered.length; i++)
      BracketPlacement(place: i + 1, managerId: ordered[i].managerId),
  ];

  return PlayoffBracket(
    winners: roundsFrom(winnerMap),
    consolation: roundsFrom(consoMap),
    placements: placements,
    playoffTeams: pt,
    startRound: startRound,
    weeksPerRound: weeksPerRound,
  );
}
