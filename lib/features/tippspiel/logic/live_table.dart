import '../../../core/models/models.dart';

/// Rechnet laufende und frisch beendete Spiele in die Ligatabelle ein.
///
/// **Warum das nötig ist:** Sportmonks schreibt die Standings nicht sofort
/// fort. Ein Spiel kann längst abgepfiffen sein, während die Tabelle noch den
/// Stand von davor zeigt — für eine Ansicht, die „Live" heißt, ist das falsch.
///
/// **Warum die API-Tabelle trotzdem die Grundlage bleibt** und nicht einfach
/// alles aus den Spielen gerechnet wird: Sie enthält Dinge, die aus Ergebnissen
/// nicht ableitbar sind — allen voran **Punktabzüge** (Lizenzauflagen,
/// Verbandsstrafen). Wer die Tabelle komplett selbst rechnet, verliert die
/// stillschweigend.
///
/// Verrechnet werden deshalb nur die Spiele, die in der API-Tabelle noch
/// **fehlen**: Je Mannschaft wird gezählt, wie viele beendete Spiele der
/// Spielplan kennt, und mit `played` der Tabelle verglichen. Ist der Spielplan
/// weiter, werden die jüngsten Begegnungen bis zur Differenz nachgetragen.
/// Laufende Spiele kommen über [includeLive] mit ihrem Zwischenstand dazu.
List<StandingRow> mergeLiveResults(
  List<StandingRow> base,
  List<Fixture> fixtures, {
  bool includeLive = true,
}) {
  if (base.isEmpty) return base;

  final byTeam = {for (final r in base) r.team.id: _Acc.from(r)};

  // Beendete Spiele je Mannschaft, jüngste zuerst — daraus wird der Rückstand
  // der API-Tabelle aufgefüllt.
  final beendet = <String, List<Fixture>>{};
  final laufend = <Fixture>[];
  for (final f in fixtures) {
    if (f.homeScore == null || f.awayScore == null) continue;
    if (f.status == FixtureStatus.finished) {
      beendet.putIfAbsent(f.home.id, () => []).add(f);
      beendet.putIfAbsent(f.away.id, () => []).add(f);
    } else if (f.status == FixtureStatus.live) {
      laufend.add(f);
    }
  }
  for (final list in beendet.values) {
    list.sort((a, b) => b.kickoff.compareTo(a.kickoff));
  }

  // Ein Spiel darf nur einmal einfließen, auch wenn beide Mannschaften es als
  // fehlend melden.
  final verrechnet = <String>{};
  for (final entry in byTeam.entries) {
    final gespieltLautPlan = (beendet[entry.key] ?? const []).length;
    final fehlend = gespieltLautPlan - entry.value.played;
    if (fehlend <= 0) continue;
    for (final f in (beendet[entry.key] ?? const []).take(fehlend)) {
      if (!verrechnet.add(f.id)) continue;
      _buche(byTeam, f);
    }
  }

  if (includeLive) {
    for (final f in laufend) {
      _buche(byTeam, f);
    }
  }

  final rows = byTeam.values.map((a) => a.toRow()).toList()
    ..sort((a, b) {
      // Bundesliga-Reihung: Punkte, dann Tordifferenz, dann erzielte Tore.
      final p = b.points.compareTo(a.points);
      if (p != 0) return p;
      final d = (b.goalsFor - b.goalsAgainst)
          .compareTo(a.goalsFor - a.goalsAgainst);
      if (d != 0) return d;
      final g = b.goalsFor.compareTo(a.goalsFor);
      if (g != 0) return g;
      return a.team.name.toLowerCase().compareTo(b.team.name.toLowerCase());
    });

  return [
    for (final (i, r) in rows.indexed)
      StandingRow(
        rank: i + 1,
        team: r.team,
        points: r.points,
        played: r.played,
        won: r.won,
        draw: r.draw,
        lost: r.lost,
        goalsFor: r.goalsFor,
        goalsAgainst: r.goalsAgainst,
      )
  ];
}

void _buche(Map<String, _Acc> byTeam, Fixture f) {
  final h = byTeam[f.home.id];
  final a = byTeam[f.away.id];
  // Mannschaften, die die Tabelle nicht kennt (Pokal-Gegner aus anderer Liga),
  // gehören nicht in diese Tabelle.
  if (h == null || a == null) return;
  final hs = f.homeScore!;
  final as_ = f.awayScore!;
  h.add(scored: hs, conceded: as_);
  a.add(scored: as_, conceded: hs);
}

/// Veränderlicher Zwischenstand einer Tabellenzeile.
class _Acc {
  _Acc({
    required this.team,
    required this.points,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
  });

  factory _Acc.from(StandingRow r) => _Acc(
        team: r.team,
        points: r.points,
        played: r.played,
        won: r.won,
        draw: r.draw,
        lost: r.lost,
        goalsFor: r.goalsFor,
        goalsAgainst: r.goalsAgainst,
      );

  final TeamRef team;
  int points;
  int played;
  int won;
  int draw;
  int lost;
  int goalsFor;
  int goalsAgainst;

  void add({required int scored, required int conceded}) {
    played += 1;
    goalsFor += scored;
    goalsAgainst += conceded;
    if (scored > conceded) {
      won += 1;
      points += 3;
    } else if (scored == conceded) {
      draw += 1;
      points += 1;
    } else {
      lost += 1;
    }
  }

  StandingRow toRow() => StandingRow(
        rank: 0, // wird nach dem Sortieren gesetzt
        team: team,
        points: points,
        played: played,
        won: won,
        draw: draw,
        lost: lost,
        goalsFor: goalsFor,
        goalsAgainst: goalsAgainst,
      );
}
