import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/round_robin.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// 30.10.2026, auf Ansage: Ohne Remis-Regel steht die Tabelle als Bilanz
/// wie in der NFL; dazu das Vereins-Limit im Kader.
void main() {
  test('Bilanz: nach Siegquote, Unentschieden zählt halb', () {
    const a = H2HRecord(managerId: 'a', wins: 5, losses: 2);
    const b = H2HRecord(managerId: 'b', wins: 5, losses: 1, ties: 1);
    expect(a.nflBilanz, '5-2');
    expect(b.nflBilanz, '5-1-1');
    expect(b.siegquote, greaterThan(a.siegquote));
  });

  test('Spielfrei verzerrt die Bilanz nicht, die Punkte schon', () {
    // Drei Teilnehmer: je Spieltag hat einer frei.
    final ids = ['a', 'b', 'c'];
    final summen = <int, Map<String, num>>{
      for (var r = 1; r <= 3; r++) r: {'a': 100, 'b': 50, 'c': 10},
    };
    final bilanz = h2hStandings(ids, summen, bilanz: true);
    expect(bilanz.first.managerId, 'a');
    expect(bilanz.first.losses, 0);
    final punkte = h2hStandings(ids, summen);
    expect(punkte.first.managerId, 'a');
  });

  test('Vereins-Limit: in der JSONB nur, wenn gesetzt', () {
    const ohne = RosterConfig();
    expect(ohne.toJson().containsKey('maxJeVerein'), isFalse);
    final mit = RosterConfig.fromJson({...ohne.toJson(), 'maxJeVerein': 3});
    expect(mit.maxJeVerein, 3);
    expect(mit.toJson()['maxJeVerein'], 3);
    // Runden ändern behält das Limit.
    expect(mit.withRounds(20).maxJeVerein, 3);
  });
}
