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


/// **Ein Trade ist ein Ereignis, nicht zwei.**
///
/// [vorgaengeAus] hält die Seiten bewusst getrennt — für „Meine Wechsel" ist
/// die eigene Sicht die richtige. In der Liga-Liste standen dadurch aber zwei
/// Karten für denselben Tausch, spiegelverkehrt: „Eric +Guirassy −Amiri" über
/// „Majusch +Amiri −Guirassy". Dieselbe Auskunft zweimal.
class TransferEreignis {
  const TransferEreignis(this.seiten);

  /// Eine Seite bei Free Agency, Waiver und Drop; zwei bei einem Trade.
  final List<TransferVorgang> seiten;

  DateTime get passiertAm => seiten.first.passiertAm;
  String? get weg => seiten.first.weg;
  bool get istTrade => seiten.length > 1;
}

/// Fasst die Vorgänge zu Ereignissen zusammen, jüngste zuerst.
///
/// **Zusammengeführt wird über den tatsächlichen Tausch, nicht über die Zeit
/// allein.** Das ist der Punkt, an dem eine naheliegende Lösung falsch wäre:
/// `fantasy_faellige_trades_ausfuehren` (Migration 0088) arbeitet **alle**
/// fälligen Trades in einer Transaktion ab — sie tragen damit denselben
/// Zeitstempel. Wer nur nach Zeit gruppiert, klebt fremde Tausche aneinander
/// und zeigt Manager als Partner, die nie miteinander gehandelt haben.
///
/// Maßgeblich ist deshalb: Die Gegenseite ist die, deren **Zugänge genau meine
/// Abgänge** sind und umgekehrt.
List<TransferEreignis> ereignisseAus(List<RosterMove> moves) {
  final vorgaenge = vorgaengeAus(moves);
  final offen = [...vorgaenge];
  final out = <TransferEreignis>[];

  Set<String> ids(List<RosterMove> xs) => {for (final m in xs) m.playerId};

  while (offen.isNotEmpty) {
    final a = offen.removeAt(0);
    if (a.weg != 'trade') {
      out.add(TransferEreignis([a]));
      continue;
    }
    final passt = offen.indexWhere((b) =>
        b.weg == 'trade' &&
        b.passiertAm == a.passiertAm &&
        b.managerId != a.managerId &&
        _gleich(ids(b.rein), ids(a.raus)) &&
        _gleich(ids(b.raus), ids(a.rein)));
    if (passt == -1) {
      // Die Gegenseite fehlt — etwa weil sie aus der Rückfüllung nicht
      // rekonstruiert werden konnte. Dann steht die eine Seite allein da,
      // statt sie einer falschen zuzuschlagen.
      out.add(TransferEreignis([a]));
    } else {
      out.add(TransferEreignis([a, offen.removeAt(passt)]));
    }
  }
  out.sort((x, y) => y.passiertAm.compareTo(x.passiertAm));
  return out;
}

bool _gleich(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
