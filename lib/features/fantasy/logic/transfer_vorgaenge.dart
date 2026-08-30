import '../models/roster_move.dart';

/// **Ein Vorgang statt zwei Zeilen.**
///
/// Wer einen Spieler holt, gibt meist im selben Atemzug einen ab. Im Protokoll
/// sind das zwei Zeilen (`fantasy_roster_moves`, Migration 0096), und
/// nebeneinander gestellt sahen sie aus wie zwei unabhängige Ereignisse: „X
/// verpflichtet" über „Y abgegeben", ohne dass etwas sagt, dass Y **für** X
/// gehen musste. Genau das ist aber die Auskunft, die man sucht.
///
/// Zusammengefasst wird über **Manager und Zeitstempel**. Das ist keine
/// Schätzung: Beide Zeilen entstehen in derselben Transaktion, und
/// Postgres' `now()` liefert die Transaktionszeit — die Werte sind exakt
/// gleich. Nachgemessen an einem echten Trade: beide Zeilen auf
/// `05:47:17.294999`.
class TransferVorgang {
  const TransferVorgang({
    required this.managerId,
    required this.passiertAm,
    required this.rein,
    required this.raus,
  });

  final String managerId;
  final DateTime passiertAm;

  /// Was in den Kader kam (meist genau einer, bei einem Mehrfach-Trade auch
  /// mehrere).
  final List<RosterMove> rein;

  /// Was den Kader verlassen hat.
  final List<RosterMove> raus;

  /// Wie der Vorgang zustande kam — `draft`, `fa`, `waiver`, `trade` oder
  /// `null` für einen reinen Abgang.
  String? get weg =>
      rein.isNotEmpty ? rein.first.weg : (raus.isEmpty ? null : raus.first.weg);

  /// Ein reiner Abgang ohne Gegenwert: jemand hat schlicht gedroppt.
  bool get nurAbgang => rein.isEmpty && raus.isNotEmpty;

  String get bezeichnung {
    if (nurAbgang) return raus.first.weg == 'trade' ? 'Getradet' : 'Abgegeben';
    return rein.first.bezeichnung;
  }
}

/// Fasst die Bewegungen zu Vorgängen zusammen, jüngste zuerst.
///
/// **Je Manager getrennt**, auch wenn ein Trade beide Seiten im selben
/// Augenblick bewegt: „Eric bekommt Guirassy und gibt Amiri" und „Majusch
/// bekommt Amiri und gibt Guirassy" sind zwei Auskünfte, nicht eine.
List<TransferVorgang> vorgaengeAus(List<RosterMove> moves) {
  final gruppen = <String, List<RosterMove>>{};
  for (final m in moves) {
    // Der Schlüssel trägt die Zeit auf die Mikrosekunde genau — gerundet
    // würden zwei getrennte Vorgänge derselben Minute zusammenfallen.
    final key = '${m.managerId}|${m.passiertAm.microsecondsSinceEpoch}';
    (gruppen[key] ??= []).add(m);
  }

  final out = [
    for (final eintraege in gruppen.values)
      TransferVorgang(
        managerId: eintraege.first.managerId,
        passiertAm: eintraege.first.passiertAm,
        rein: [
          for (final m in eintraege)
            if (m.zugang) m
        ],
        raus: [
          for (final m in eintraege)
            if (!m.zugang) m
        ],
      )
  ];
  out.sort((a, b) => b.passiertAm.compareTo(a.passiertAm));
  return out;
}

/// Wo steckt ein abgegebener Spieler jetzt?
///
/// Die Frage stellt sich sofort, wenn man einen Abgang liest: **Kann ich ihn
/// holen?** Drei Antworten, und alle drei sind verschieden — sie in eine zu
/// gießen („nicht im Kader") wäre die unbrauchbare.
enum Marktlage {
  /// Liegt 24 Stunden auf dem Waiver — nur per Antrag.
  aufDemWaiver,

  /// Frei: direkt holbar.
  frei,

  /// Hat schon jemand anders.
  vergeben,
}

Marktlage marktlage(
  String playerId, {
  required Set<String> aufWaiver,
  required Set<String> imKader,
}) {
  if (imKader.contains(playerId)) return Marktlage.vergeben;
  if (aufWaiver.contains(playerId)) return Marktlage.aufDemWaiver;
  return Marktlage.frei;
}
