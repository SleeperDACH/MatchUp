/// Head-to-Head-Spielplan und -Bilanz (sport-/feature-agnostisch).
///
/// Pro Spieltag werden die Teilnehmer 1-gegen-1 gepaart (Round-Robin nach der
/// Kreismethode). Der Spielplan ist **deterministisch** aus der stabilen
/// Reihenfolge der Teilnehmer-IDs ableitbar — daher keine eigene Tabelle
/// nötig: über n-1 Spieltage spielt jeder gegen jeden genau einmal, danach
/// wiederholt sich der Zyklus. Bei ungerader Teilnehmerzahl hat pro Spieltag
/// einer spielfrei (Bye). Genutzt von Fantasy (Manager) und Tippspiel
/// (Mitglieder) gleichermaßen.
library;

/// Eine Paarung eines Spieltags. [away] == null ⇒ spielfrei (Bye).
class Matchup {
  const Matchup(this.home, this.away);

  final String home;
  final String? away;

  bool get isBye => away == null;
}

/// Round-Robin-Paarungen für [round] (1-basiert) aus der stabilen
/// Reihenfolge [ids] (z. B. nach Draft-Position sortiert).
List<Matchup> roundPairings(List<String> ids, int round) {
  if (ids.length < 2) return const [];

  // Bei ungerader Zahl ein Bye-Slot (null) ergänzen.
  final slots = <String?>[...ids];
  if (slots.length.isOdd) slots.add(null);
  final n = slots.length;

  // Kreismethode: Slot 0 bleibt fix, die übrigen rotieren je Spieltag.
  final rot = (round - 1) % (n - 1);
  final rest = slots.sublist(1);
  final rotated = [
    ...rest.sublist(rest.length - rot),
    ...rest.sublist(0, rest.length - rot),
  ];
  final arranged = <String?>[slots.first, ...rotated];

  final pairs = <Matchup>[];
  for (var i = 0; i < n ~/ 2; i++) {
    final a = arranged[i];
    final b = arranged[n - 1 - i];
    if (a == null && b == null) continue;
    // Der reale Teilnehmer ist „home"; fehlt der Gegner, ist es ein Bye.
    if (a == null) {
      pairs.add(Matchup(b!, null));
    } else {
      pairs.add(Matchup(a, b));
    }
  }
  return pairs;
}

/// Bilanz eines Teilnehmers im Head-to-Head.
class H2HRecord {
  const H2HRecord({
    required this.managerId,
    this.wins = 0,
    this.losses = 0,
    this.ties = 0,
    this.pointsFor = 0,
    this.pointsAgainst = 0,
  });

  final String managerId;
  final int wins;
  final int losses;
  final int ties;
  final int pointsFor;
  final int pointsAgainst;

  int get played => wins + losses + ties;

  H2HRecord _add({
    int win = 0,
    int loss = 0,
    int tie = 0,
    int pf = 0,
    int pa = 0,
  }) =>
      H2HRecord(
        managerId: managerId,
        wins: wins + win,
        losses: losses + loss,
        ties: ties + tie,
        pointsFor: pointsFor + pf,
        pointsAgainst: pointsAgainst + pa,
      );
}

/// Bilanztabelle aus den Paarungen und den (effektiven) Punkten je
/// gespieltem Spieltag. [totalsByRound] enthält nur gespielte Spieltage
/// (Teilnehmer-ID → Punkte). Sortiert nach Siegen, dann Punktedifferenz, dann
/// erzielten Punkten.
List<H2HRecord> h2hStandings(
  List<String> ids,
  Map<int, Map<String, int>> totalsByRound,
) {
  var records = {for (final id in ids) id: H2HRecord(managerId: id)};

  for (final entry in totalsByRound.entries) {
    final totals = entry.value;
    for (final m in roundPairings(ids, entry.key)) {
      if (m.isBye) continue; // spielfrei zählt nicht
      final hp = totals[m.home] ?? 0;
      final ap = totals[m.away] ?? 0;
      if (hp > ap) {
        records[m.home] = records[m.home]!._add(win: 1, pf: hp, pa: ap);
        records[m.away!] = records[m.away]!._add(loss: 1, pf: ap, pa: hp);
      } else if (ap > hp) {
        records[m.home] = records[m.home]!._add(loss: 1, pf: hp, pa: ap);
        records[m.away!] = records[m.away]!._add(win: 1, pf: ap, pa: hp);
      } else {
        records[m.home] = records[m.home]!._add(tie: 1, pf: hp, pa: ap);
        records[m.away!] = records[m.away]!._add(tie: 1, pf: ap, pa: hp);
      }
    }
  }

  final list = records.values.toList();
  list.sort((a, b) {
    if (a.wins != b.wins) return b.wins.compareTo(a.wins);
    final da = a.pointsFor - a.pointsAgainst;
    final db = b.pointsFor - b.pointsAgainst;
    if (da != db) return db.compareTo(da);
    return b.pointsFor.compareTo(a.pointsFor);
  });
  return list;
}
