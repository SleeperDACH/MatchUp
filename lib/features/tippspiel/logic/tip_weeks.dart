import '../../../core/models/models.dart';

/// Wochen-Achse für Multi-Wettbewerb-Tipprunden: bündelt die Spiele aller
/// Wettbewerbe einer Runde in „Fußball-Wochen" (Donnerstag–Mittwoch), statt
/// je Wettbewerb nach Spieltag zu navigieren. Pure Dart (kein Flutter), damit
/// die Gruppierung testbar bleibt — wie [totalPointsByMember] in round_table.dart.
///
/// Wochen-Grenze: Donnerstag 00:00 (lokal) bis zum folgenden Mittwoch 23:59.
/// So bleibt ein Fr–Mo-Wochenende zusammen und die darauf folgenden Di/Mi-Spiele
/// einer Englischen Woche zählen mit dazu.

/// Eine Spielwoche mit fortlaufender Nummer und den enthaltenen Fixtures.
class TipWeek {
  const TipWeek({
    required this.index,
    required this.start,
    required this.end,
    required this.fixtures,
  });

  /// 1-basierte Nummer über die nicht-leeren Wochen der Saison (keine Lücken).
  final int index;

  /// Verankerter Donnerstag 00:00 lokal (inklusiv).
  final DateTime start;

  /// Folgender Donnerstag 00:00 lokal (exklusiv) — also start + 7 Tage.
  final DateTime end;

  /// Spiele der Woche (aller Wettbewerbe), nach Anstoß sortiert.
  final List<Fixture> fixtures;
}

/// Verankert einen (lokalen) Anstoßzeitpunkt auf den Donnerstag 00:00 der
/// zugehörigen Fußball-Woche (der Donnerstag am/vor dem Anstoß). Rechnet über
/// das Kalenderdatum (nicht per Duration), damit Sommer-/Winterzeit-Wechsel
/// nicht um eine Stunde verschieben.
DateTime weekStartFor(DateTime kickoffLocal) {
  final daysSinceThursday = (kickoffLocal.weekday - DateTime.thursday + 7) % 7;
  return DateTime(
      kickoffLocal.year, kickoffLocal.month, kickoffLocal.day - daysSinceThursday);
}

/// Bündelt alle Fixtures (Union über die Wettbewerbe der Runde) zu Wochen.
/// Nur Wochen mit mindestens einem Spiel, chronologisch sortiert und
/// fortlaufend nummeriert (1..K, ohne Lücken).
List<TipWeek> buildWeeks(List<Fixture> all) {
  final byStart = <DateTime, List<Fixture>>{};
  for (final f in all) {
    final start = weekStartFor(f.kickoff.toLocal());
    (byStart[start] ??= <Fixture>[]).add(f);
  }
  final starts = byStart.keys.toList()..sort();
  final weeks = <TipWeek>[];
  for (var i = 0; i < starts.length; i++) {
    final start = starts[i];
    final fixtures = byStart[start]!
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    weeks.add(TipWeek(
      index: i + 1,
      start: start,
      end: DateTime(start.year, start.month, start.day + 7),
      fixtures: fixtures,
    ));
  }
  return weeks;
}

/// Standard-Woche beim Öffnen: die früheste Woche mit einem noch nicht
/// angepfiffenen Spiel; ist die Saison vorbei, die letzte Woche. Leere Liste
/// ⇒ 1 (die UI zeigt dann ohnehin einen Leerzustand).
int currentWeekIndex(List<TipWeek> weeks, DateTime now) {
  if (weeks.isEmpty) return 1;
  final nowUtc = now.toUtc();
  for (final w in weeks) {
    if (w.fixtures.any((f) => f.kickoff.toUtc().isAfter(nowUtc))) {
      return w.index;
    }
  }
  return weeks.last.index;
}
