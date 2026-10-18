import '../../../core/logic/round_robin.dart';

/// Ausgang eines gewerteten Duells aus Sicht des Managers.
enum DuellAusgang { sieg, unentschieden, niederlage }

/// Ein Spieltag im Saisonverlauf eines Managers.
class SaisonSpiel {
  const SaisonSpiel({
    required this.runde,
    required this.gegnerId,
    this.eigene,
    this.gegner,
    this.remisGrenze = 0,
  });

  /// Höchster Abstand, der noch Unentschieden ist (Ligaeinstellung).
  final num remisGrenze;

  final int runde;

  /// `null` heißt spielfrei — bei ungerader Teilnehmerzahl hat je Spieltag
  /// einer kein Duell.
  final String? gegnerId;

  /// Punkte beider Seiten, nur für **gewertete** Spieltage gesetzt.
  final double? eigene;
  final double? gegner;

  bool get spielfrei => gegnerId == null;
  bool get gewertet => eigene != null && gegner != null;

  DuellAusgang? get ausgang {
    if (!gewertet) return null;
    return switch (duellErgebnis(eigene!, gegner!, remisGrenze: remisGrenze)) {
      > 0 => DuellAusgang.sieg,
      < 0 => DuellAusgang.niederlage,
      _ => DuellAusgang.unentschieden,
    };
  }
}

/// Der Saisonverlauf eines Managers: jeder Spieltag der regulären Saison mit
/// Gegner, und wo gewertet, mit beiden Punktzahlen.
///
/// **Dieselbe Rechnung wie die Tabelle**, nicht eine zweite: Die Paarungen
/// kommen aus [roundPairings] über dieselbe Reihenfolge [ids], die Punkte aus
/// demselben [gewertet] (nur abgepfiffene Spieltage, siehe
/// `gewerteteRunden`). Liefe das hier anders, stünde im Profil eine Bilanz,
/// die der Tabelle widerspricht.
///
/// [letzteRunde] ist das Ende der **regulären** Saison — die Playoff-Spieltage
/// danach paart der Round-Robin nicht, dort entscheidet das Bracket.
List<SaisonSpiel> saisonverlauf({
  required List<String> ids,
  required String managerId,
  required Map<int, Map<String, num>> gewertet,
  required int letzteRunde,
  num remisGrenze = 0,
}) {
  if (!ids.contains(managerId)) return const [];
  final out = <SaisonSpiel>[];
  for (var runde = 1; runde <= letzteRunde; runde++) {
    String? gegnerId;
    var gefunden = false;
    for (final m in roundPairings(ids, runde)) {
      if (m.home == managerId) {
        gegnerId = m.away;
        gefunden = true;
        break;
      }
      if (m.away == managerId) {
        gegnerId = m.home;
        gefunden = true;
        break;
      }
    }
    if (!gefunden) continue;
    final totals = gewertet[runde];
    // Spielfrei wird nicht gewertet — dieselbe Regel wie in `h2hStandings`.
    final mitPunkten = totals != null && gegnerId != null;
    out.add(
      SaisonSpiel(
        runde: runde,
        gegnerId: gegnerId,
        eigene: mitPunkten ? (totals[managerId] ?? 0).toDouble() : null,
        gegner: mitPunkten ? (totals[gegnerId] ?? 0).toDouble() : null,
        remisGrenze: remisGrenze,
      ),
    );
  }
  return out;
}

/// Die laufende Serie: wie oft hintereinander zuletzt derselbe Ausgang.
///
/// Gezählt wird rückwärts über die **gewerteten** Duelle; spielfreie Spieltage
/// unterbrechen nicht, sie zählen nur nicht. `null`, solange nichts gewertet
/// ist.
({DuellAusgang ausgang, int anzahl})? serie(List<SaisonSpiel> verlauf) {
  final gewertet = [for (final s in verlauf) if (s.gewertet) s];
  if (gewertet.isEmpty) return null;
  final letzter = gewertet.last.ausgang!;
  var anzahl = 0;
  for (final s in gewertet.reversed) {
    if (s.ausgang != letzter) break;
    anzahl++;
  }
  return (ausgang: letzter, anzahl: anzahl);
}
