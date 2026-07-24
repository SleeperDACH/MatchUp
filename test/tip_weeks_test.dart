import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';
import 'package:meine_app/features/tippspiel/logic/tip_weeks.dart';

// Kickoffs bewusst als LOKALE DateTime (nicht .utc), damit `toLocal()` in der
// Wochen-Logik ein No-op ist und die Tests unabhängig von der Zeitzone der
// Testmaschine deterministisch bleiben.
Fixture _fx(String id, DateTime kickoff, {String league = 'bl1'}) => Fixture(
      id: id,
      leagueId: league,
      season: 2025,
      round: 1,
      roundName: 'Spieltag 1',
      kickoff: kickoff,
      home: const TeamRef(id: 'h', name: 'Heim', shortName: 'HEI'),
      away: const TeamRef(id: 'a', name: 'Aus', shortName: 'AUS'),
      status: FixtureStatus.scheduled,
    );

void main() {
  test('weekStartFor verankert auf den Donnerstag 00:00 der Fußball-Woche', () {
    // Donnerstag selbst
    expect(weekStartFor(DateTime(2025, 9, 11, 20)), DateTime(2025, 9, 11));
    // Samstag → gleicher Donnerstag
    expect(weekStartFor(DateTime(2025, 9, 13, 15, 30)), DateTime(2025, 9, 11));
    // Mittwoch → noch dieselbe Woche
    expect(weekStartFor(DateTime(2025, 9, 17, 20, 45)), DateTime(2025, 9, 11));
    // Donnerstag darauf → nächste Woche
    expect(weekStartFor(DateTime(2025, 9, 18, 18)), DateTime(2025, 9, 18));
  });

  test('buildWeeks: Fr–Mo-Wochenende + Di/Mi englische Woche in einer Woche', () {
    final weeks = buildWeeks([
      _fx('fr', DateTime(2025, 9, 12, 20, 30)),
      _fx('sa', DateTime(2025, 9, 13, 15, 30)),
      _fx('so', DateTime(2025, 9, 14, 17, 30)),
      _fx('mo', DateTime(2025, 9, 15, 20, 30)),
      _fx('di', DateTime(2025, 9, 16, 20, 30)),
      _fx('mi', DateTime(2025, 9, 17, 20, 30)),
    ]);
    expect(weeks.length, 1);
    expect(weeks.single.index, 1);
    expect(weeks.single.start, DateTime(2025, 9, 11));
    expect(weeks.single.end, DateTime(2025, 9, 18));
    expect(weeks.single.fixtures.map((f) => f.id),
        ['fr', 'sa', 'so', 'mo', 'di', 'mi']);
  });

  test('buildWeeks: mehrere Wettbewerbe gemischt, nach Anstoß sortiert', () {
    final weeks = buildWeeks([
      _fx('bl_sa', DateTime(2025, 9, 13, 15, 30), league: 'bl1'),
      _fx('pl_sa_early', DateTime(2025, 9, 13, 13, 30), league: 'pl'),
      _fx('pl_fr', DateTime(2025, 9, 12, 21, 0), league: 'pl'),
    ]);
    expect(weeks.length, 1);
    expect(weeks.single.fixtures.map((f) => f.id),
        ['pl_fr', 'pl_sa_early', 'bl_sa']);
  });

  test('buildWeeks: fortlaufende Nummern ohne Lücken trotz leerer Kalenderwoche',
      () {
    final weeks = buildWeeks([
      _fx('w1', DateTime(2025, 9, 13, 15, 30)), // Woche Do 11.09.
      // Kalenderwoche Do 18.09. bleibt leer (übersprungen)
      _fx('w3', DateTime(2025, 9, 27, 15, 30)), // Woche Do 25.09.
    ]);
    expect(weeks.map((w) => w.index), [1, 2]);
    expect(weeks[0].start, DateTime(2025, 9, 11));
    expect(weeks[1].start, DateTime(2025, 9, 25));
  });

  test('currentWeekIndex: früheste Woche mit noch offenem Spiel', () {
    final weeks = buildWeeks([
      _fx('past', DateTime(2025, 9, 13, 15, 30)),
      _fx('next', DateTime(2025, 9, 27, 15, 30)),
      _fx('later', DateTime(2025, 10, 4, 15, 30)),
    ]);
    // "Jetzt" liegt nach Woche 1, vor Woche 2 → aktuelle Woche = 2.
    expect(currentWeekIndex(weeks, DateTime(2025, 9, 20, 12)), 2);
    // Saison vorbei → letzte Woche.
    expect(currentWeekIndex(weeks, DateTime(2025, 11, 1)), 3);
    // Vor allem → erste Woche.
    expect(currentWeekIndex(weeks, DateTime(2025, 9, 1)), 1);
  });
}
