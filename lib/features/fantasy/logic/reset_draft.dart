import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';

/// **Reset zur Winterpause** (0143) — die reinen Regeln des zweiten Drafts.

/// Pick-Folge der ersten Runde: **der Tabellenletzte zuerst, der Erste
/// zuletzt**, danach Snake wie immer. [standings] ist die Tabelle in der
/// Reihenfolge, in der die App sie anzeigt (`h2hStandings`, Erster vorn).
List<String> resetReihenfolge(List<H2HRecord> standings) =>
    [for (final r in standings.reversed) r.managerId];

/// Die Manager, wie der Draft-Raum sie in dieser Phase sieht: in der
/// Reset-Phase mit der Reset-Position als Draft-Position.
///
/// `draft_position` bleibt dabei unangetastet — an ihr hängen die
/// Duell-Paarungen der ganzen Saison. Der Draft-Raum bekommt nur eine Sicht,
/// damit er selbst nichts von zwei Positionen wissen muss.
List<FantasyManager> managerFuerDraft(
  List<FantasyManager> managers,
  String phase,
) {
  if (phase != 'reset') return managers;
  return [
    for (final m in managers)
      m.mitDraftPosition(m.resetPosition),
  ];
}

/// Nur die Picks der laufenden Phase — die Pick-Nummern beginnen je Phase
/// wieder bei 1.
List<DraftPick> picksDerPhase(List<DraftPick> picks, String phase) =>
    [for (final p in picks) if (p.phase == phase) p];
