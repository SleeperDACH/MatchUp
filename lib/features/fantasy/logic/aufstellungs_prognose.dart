import 'package:matchup/core/models/models.dart';

/// **Welches Spiel zeigt die Aufstellungsprognose?**
///
/// Die Regel steht hier als reine Funktion, weil sie eine Entscheidung ist und
/// keine Anzeige: „das nächste Spiel des Vereins" wäre die naheliegende und
/// falsche Antwort. Spielt Dortmund freitags und der Spieltag endet sonntags,
/// stünde ab Freitagabend die Prognose für den *nächsten* Spieltag da — für
/// den es zu diesem Zeitpunkt noch gar keine gibt, und sie verdrängte die
/// Aufstellung, die gerade noch auf dem Platz steht.
///
/// Maßgeblich ist deshalb der **Spieltag**, nicht der Verein: Gezeigt wird die
/// laufende Runde, bis deren letztes Spiel abgepfiffen ist; danach die nächste.
Fixture? spielFuerPrognose(List<Fixture> spiele, String verein) {
  final runde = aktiveRunde(spiele);
  if (runde == null) return null;

  // Der Verein kann in der aktiven Runde spielfrei sein (Pokal-Wochenende,
  // verlegte Partie, ein Spieler aus einem Verein ohne Ansetzung). Dann gilt
  // sein nächstes Spiel — sonst stünde das Profil ohne Auskunft da, obwohl es
  // eine gibt.
  //
  // **Und er kann sein Spiel des laufenden Spieltags schon hinter sich
  // haben.** Bayern spielt freitags, der Spieltag endet sonntags: Von Freitag
  // 22 Uhr bis Sonntagabend stünde hier sonst eine bereits gespielte Partie
  // mit dem Hinweis, die Aufstellung komme noch. Fuer dieses Spiel ist nichts
  // mehr zu entscheiden — dann gilt das nächste.
  final inRunde = _fuerVerein(spiele, verein).where(
      (f) => f.round == runde && f.status != FixtureStatus.finished);
  if (inRunde.isNotEmpty) return _frueheste(inRunde.toList());

  final offen = _fuerVerein(spiele, verein)
      .where((f) => f.status != FixtureStatus.finished)
      .toList();
  return offen.isEmpty ? null : _frueheste(offen);
}

/// Die Runde, die gerade zählt: die **niedrigste, die noch nicht vollständig
/// abgepfiffen ist**.
///
/// Genau daran hängt der vom Nutzer gewünschte Umschaltzeitpunkt — nach dem
/// Abpfiff des letzten Spiels eines Spieltags rückt die Prognose weiter.
int? aktiveRunde(List<Fixture> spiele) {
  int? kleinste;
  for (final f in spiele) {
    if (f.status == FixtureStatus.finished) continue;
    if (kleinste == null || f.round < kleinste) kleinste = f.round;
  }
  return kleinste;
}

/// Das Spiel, aus dem die zuletzt **tatsächliche** Aufstellung stammt — die
/// Rückfallebene für die Tage ohne Prognose.
///
/// Sportmonks stellt die voraussichtliche Elf erst ein bis zwei Tage vor
/// Anpfiff bereit (gemessen 29.08.2026). Zwischen Abpfiff und Prognose liegen
/// also mehrere Tage, an denen die Frage „spielt er?" trotzdem gestellt wird.
/// „Zuletzt stand er in der Startelf" ist darauf eine echte Antwort.
Fixture? letztesGespieltes(List<Fixture> spiele, String verein) {
  final fertig = _fuerVerein(spiele, verein)
      .where((f) => f.status == FixtureStatus.finished)
      .toList();
  if (fertig.isEmpty) return null;
  fertig.sort((a, b) => b.kickoff.compareTo(a.kickoff));
  return fertig.first;
}

Iterable<Fixture> _fuerVerein(List<Fixture> spiele, String verein) =>
    spiele.where((f) => f.home.name == verein || f.away.name == verein);

Fixture _frueheste(List<Fixture> xs) {
  xs.sort((a, b) => a.kickoff.compareTo(b.kickoff));
  return xs.first;
}

/// Ein Spieler in der voraussichtlichen Elf.
class PrognoseSpieler {
  const PrognoseSpieler({
    required this.playerId,
    required this.name,
    this.nummer,
    this.formationsPosition,
    this.reihe,
    this.spalte,
  });

  final String playerId;
  final String name;
  final int? nummer;

  /// 1 bis 11, von hinten nach vorn — die Reihenfolge, in der Sportmonks die
  /// Elf aufstellt.
  final int? formationsPosition;

  /// Der Platz im Formationsraster, aus `formation_field` („Reihe:Spalte").
  /// Reihe 1 ist der Torwart, dann nach vorn. Gemessen an Dortmund gegen HSV:
  /// Felix Nmecha steht auf „3:3" — dritte Reihe der 3-4-2-1, dritter von
  /// links. Damit lässt sich die Elf hinstellen, statt sie zu raten.
  final int? reihe;
  final int? spalte;
}

/// Die voraussichtliche Elf eines Vereins für ein bestimmtes Spiel.
class PrognoseElf {
  const PrognoseElf({
    required this.club,
    required this.elf,
    this.formation,
    this.stand,
  });

  final String club;
  final List<PrognoseSpieler> elf;

  /// „3-4-2-1" — kommt aus einem eigenen Sportmonks-Include und kann fehlen.
  final String? formation;

  /// Wann die Prognose zuletzt geändert wurde. Sie wird bis kurz vor Anpfiff
  /// mehrfach nachgezogen; ohne den Stand wüsste niemand, wie frisch sie ist.
  final DateTime? stand;

  bool enthaelt(String playerId) =>
      elf.any((s) => s.playerId == playerId);

  /// Die Elf in **Reihen**, von hinten nach vorn — Reihe 0 ist der Torwart.
  ///
  /// Grundlage ist das Raster aus `formation_field`. Fehlt es (ältere Zeilen,
  /// unvollständige Antwort), wird nach `formationsPosition` in Blöcke
  /// geschnitten, die der Formationszeichenkette entsprechen; fehlt auch die,
  /// bleibt eine einzige Reihe. **Kein Fall darf Spieler verlieren** — eine
  /// unvollständige Formation ist besser als eine, in der jemand fehlt.
  List<List<PrognoseSpieler>> get reihen {
    if (elf.any((s) => s.reihe != null)) {
      final nach = <int, List<PrognoseSpieler>>{};
      for (final s in elf) {
        (nach[s.reihe ?? 99] ??= []).add(s);
      }
      final schluessel = nach.keys.toList()..sort();
      return [
        for (final k in schluessel)
          nach[k]!
            ..sort((a, b) => (a.spalte ?? 99).compareTo(b.spalte ?? 99))
      ];
    }

    final bloecke = _formationsBloecke(formation);
    if (bloecke == null) return [elf];
    final sortiert = [...elf]..sort((a, b) =>
        (a.formationsPosition ?? 99).compareTo(b.formationsPosition ?? 99));
    final out = <List<PrognoseSpieler>>[];
    var i = 0;
    for (final n in bloecke) {
      if (i >= sortiert.length) break;
      out.add(sortiert.sublist(i, (i + n).clamp(0, sortiert.length)));
      i += n;
    }
    // Was das Raster nicht aufnimmt, kommt trotzdem mit.
    if (i < sortiert.length) out.add(sortiert.sublist(i));
    return out;
  }

  /// Baut die Elf aus den Zeilen der Sicht `predicted_lineups_v`.
  ///
  /// Steht hier und nicht im Provider, damit es prüfbar ist: Das Lesen einer
  /// Serverantwort ist die Stelle, an der ein falscher Typ erst auf dem Gerät
  /// auffällt — und dort als leerer Reiter, nicht als Fehler.
  static PrognoseElf? ausZeilen(String club, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;

    final elf = [
      for (final r in rows)
        PrognoseSpieler(
          playerId: r['player_id'] as String,
          name: (r['player_name'] as String?) ?? '',
          nummer: (r['jersey_number'] as num?)?.toInt(),
          formationsPosition: (r['formation_position'] as num?)?.toInt(),
          reihe: _rasterTeil(r['formation_field'], 0),
          spalte: _rasterTeil(r['formation_field'], 1),
        )
    ]..sort((a, b) =>
        (a.formationsPosition ?? 99).compareTo(b.formationsPosition ?? 99));

    DateTime? neuster;
    String? formation;
    for (final r in rows) {
      formation ??= r['formation'] as String?;
      final t = DateTime.tryParse((r['updated_at'] as String?) ?? '');
      if (t != null && (neuster == null || t.isAfter(neuster))) neuster = t;
    }

    return PrognoseElf(
      club: club,
      elf: elf,
      formation: formation,
      stand: neuster?.toLocal(),
    );
  }
}

/// Liest „Reihe:Spalte" aus `formation_field`. [teil] 0 = Reihe, 1 = Spalte.
int? _rasterTeil(Object? feld, int teil) {
  if (feld is! String) return null;
  final stuecke = feld.split(':');
  if (stuecke.length <= teil) return null;
  return int.tryParse(stuecke[teil].trim());
}

/// „3-4-2-1" → [1, 3, 4, 2, 1] — der Torwart kommt vorn dazu.
List<int>? _formationsBloecke(String? formation) {
  if (formation == null || formation.isEmpty) return null;
  final zahlen = [
    for (final t in formation.split('-')) int.tryParse(t.trim())
  ];
  if (zahlen.isEmpty || zahlen.any((z) => z == null)) return null;
  return [1, ...zahlen.cast<int>()];
}
