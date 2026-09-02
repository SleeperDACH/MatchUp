/// Eine **Kaderbewegung**: ein Spieler kommt in einen Kader oder verlässt ihn.
///
/// Kommt aus `fantasy_roster_moves` (Migration 0096). Vorher gab es dafür
/// keine Quelle: `fantasy_rosters` kennt nur den Bestand, und wer einen Kader
/// verlässt, verschwindet spurlos — die Hälfte der Auskunft, die man sucht.
class RosterMove {
  const RosterMove({
    required this.id,
    required this.leagueId,
    required this.managerId,
    required this.playerId,
    required this.zugang,
    required this.passiertAm,
    this.weg,
  });

  final int id;
  final String leagueId;
  final String managerId;
  final String playerId;

  /// `true` = in den Kader, `false` = aus dem Kader.
  final bool zugang;

  /// `draft`, `fa`, `waiver`, `trade`, `abgewandert` — oder `null`.
  ///
  /// **Beim Abgang steht hier meist nichts**, und das ist Absicht: Die
  /// Datenbank sieht beim Löschen einer Kaderzeile nicht, ob ein Drop, eine
  /// Waiver-Abgabe oder eine Admin-Korrektur dahintersteckt. Etwas zu raten
  /// wäre schlimmer als nichts zu sagen. Beim Trade weiß sie es, weil dort
  /// der Besitzer wechselt statt gelöscht zu werden — und beim Abgang aus der
  /// Bundesliga (`abgewandert`), weil der Kader-Sync ihn selbst einträgt
  /// (Migration 0117).
  final String? weg;

  final DateTime passiertAm;

  factory RosterMove.fromJson(Map<String, dynamic> j) => RosterMove(
        id: (j['id'] as num).toInt(),
        leagueId: j['league_id'] as String,
        managerId: j['manager_id'] as String,
        playerId: j['player_id'] as String,
        zugang: (j['richtung'] as String?) == 'zugang',
        weg: j['weg'] as String?,
        passiertAm:
            DateTime.parse(j['passiert_am'] as String).toLocal(),
      );

  /// Wie die Bewegung heißt, wenn man sie hinschreibt.
  String get bezeichnung {
    if (!zugang) {
      return switch (weg) {
        'trade' => 'Getradet',
        // Kein Drop des Managers: Der Spieler ist aus der Liga weg.
        'abgewandert' => 'Bundesliga verlassen',
        _ => 'Abgegeben',
      };
    }
    return switch (weg) {
      'draft' => 'Gedraftet',
      'fa' => 'Verpflichtet',
      'waiver' => 'Über Waiver',
      'trade' => 'Getradet',
      _ => 'Aufgenommen',
    };
  }
}
