import 'dart:collection';

import '../../../core/models/models.dart';
import '../models/fantasy_models.dart';
import '../models/roster_move.dart';

/// **Der Kader, mit dem ein Spieltag gewertet wird** — nach einem Reset
/// (0143) nicht mehr derselbe für alle Spieltage.
///
/// Hat ein Manager für einen Spieltag keine gespeicherte Aufstellung, wertet
/// die App die beste Elf aus seinem Kader. Nach dem Reset ist der aktuelle
/// Kader der aus dem Reset-Draft — die Hinrunde stünde damit rückwirkend mit
/// fremden Spielern oder auf null da, und die Tabelle, die ausdrücklich
/// bleiben soll, liefe weg.
///
/// Nach außen ist [WertungsKader] **der aktuelle Kader** (eine Liste wie
/// vorher, für Kaderanzeige, Free Agency, Trades). Nur
/// `effectiveTotalsForRound` und `computeSideData` fragen über
/// [kaderFuerRunde] nach dem Kader eines Spieltags; für Spieltage vor dem
/// Reset ist das der Kader zum Reset-Zeitpunkt — exakt die protokollierten
/// Abgänge mit `weg = 'reset'`.
class WertungsKader extends UnmodifiableListView<RosterEntry> {
  WertungsKader(
    super.aktuell, {
    required this.vorReset,
    required this.ersteRundeNachReset,
  });

  final List<RosterEntry> vorReset;
  final int ersteRundeNachReset;

  List<RosterEntry> fuer(int runde) =>
      runde < ersteRundeNachReset ? vorReset : this;
}

/// Der Kader für [runde] — ohne Reset schlicht [roster].
List<RosterEntry> kaderFuerRunde(List<RosterEntry> roster, int runde) =>
    roster is WertungsKader ? roster.fuer(runde) : roster;

/// Der Kader zum Reset-Zeitpunkt aus dem Protokoll.
List<RosterEntry> kaderVorReset(List<RosterMove> moves) => [
      for (final m in moves)
        if (!m.zugang && m.weg == 'reset')
          RosterEntry(
            managerId: m.managerId,
            playerId: m.playerId,
            acquiredVia: 'draft',
          ),
    ];

/// Die erste Runde, die nach dem Reset-Termin beginnt (Rückrunde), oder
/// `null`, wenn der Spielplan keine kennt.
int? ersteRundeNachReset(List<Fixture> fixtures, DateTime termin) {
  int? beste;
  for (final f in fixtures) {
    final r = f.round;
    if (f.kickoff.isBefore(termin)) continue;
    if (beste == null || r < beste) beste = r;
  }
  return beste;
}

/// Kader vor dem Reset plus erste Runde danach, verglichen nach Inhalt.
class ResetKader {
  ResetKader(this.vorher, this.ersteRunde)
      : _schluessel = ([
          for (final r in vorher) '${r.managerId}:${r.playerId}'
        ]..sort())
            .join(',');

  final List<RosterEntry> vorher;
  final int ersteRunde;
  final String _schluessel;

  @override
  bool operator ==(Object other) =>
      other is ResetKader &&
      other.ersteRunde == ersteRunde &&
      other._schluessel == _schluessel;

  @override
  int get hashCode => Object.hash(ersteRunde, _schluessel);
}
