import '../models/fantasy_models.dart';
import 'draft_order.dart';

/// **Picks für den Reset-Draft** (0145) — wem welcher Pick gehört.
///
/// Ein Pick ist **Runde + ursprüngliches Team** („Runde 2 von Eric"). Die
/// Datenbank speichert nur gehandelte Picks; fehlt der Eintrag, gehört der
/// Pick seinem ursprünglichen Team. Dieselbe Regel wie
/// `fantasy_pick_besitzer` — laufen die beiden auseinander, zieht im
/// Draft-Raum ein anderer Manager, als der Server erwartet.

/// Ein gehandelter Pick (Zeile aus `fantasy_draft_rechte`).
class DraftRecht {
  const DraftRecht({
    required this.runde,
    required this.ursprung,
    required this.besitzer,
  });

  final int runde;
  final String ursprung;
  final String besitzer;

  factory DraftRecht.fromJson(Map<String, dynamic> json) => DraftRecht(
        runde: (json['runde'] as num).toInt(),
        ursprung: json['ursprung'] as String,
        besitzer: json['besitzer'] as String,
      );
}

/// Ein Pick in einem Trade-Angebot (Zeile aus `fantasy_trade_picks`):
/// [giver] gibt den Pick Runde [runde] von [ursprung] ab.
class TradePick {
  const TradePick({
    required this.tradeId,
    required this.giver,
    required this.runde,
    required this.ursprung,
  });

  final String tradeId;
  final String giver;
  final int runde;
  final String ursprung;

  factory TradePick.fromJson(Map<String, dynamic> json) => TradePick(
        tradeId: json['trade_id'] as String,
        giver: json['giver'] as String,
        runde: (json['runde'] as num).toInt(),
        ursprung: json['ursprung'] as String,
      );

  PickKey get key => (runde: runde, ursprung: ursprung);
}

/// Schlüssel eines Picks.
typedef PickKey = ({int runde, String ursprung});

/// Gehandelte Picks als Nachschlagetabelle.
Map<PickKey, String> rechteKarte(Iterable<DraftRecht> rechte) => {
      for (final r in rechte) (runde: r.runde, ursprung: r.ursprung): r.besitzer,
    };

/// Wem gehört Runde [runde] von [ursprung]?
String besitzerVon(Map<PickKey, String> rechte, int runde, String ursprung) =>
    rechte[(runde: runde, ursprung: ursprung)] ?? ursprung;

/// Ein Feld des Reset-Draft-Boards.
class PickSlot {
  const PickSlot({
    required this.runde,
    required this.nummerInRunde,
    required this.ursprung,
    required this.besitzer,
  });

  final int runde;

  /// 1-basiert, nach Snake (ungerade Runden vorwärts, gerade rückwärts).
  final int nummerInRunde;
  final String ursprung;
  final String besitzer;

  bool get gehandelt => besitzer != ursprung;

  /// „2.05" — dieselbe Schreibweise wie auf dem Draft-Board.
  String get code => pickCode(runde, nummerInRunde);

  PickKey get key => (runde: runde, ursprung: ursprung);
}

String pickCode(int runde, int nummerInRunde) =>
    '$runde.${nummerInRunde.toString().padLeft(2, '0')}';

/// Alle Picks des Reset-Drafts. [reihenfolge] ist die Folge der ersten Runde
/// (Tabellenletzter zuerst, `resetReihenfolge`), danach Snake.
List<PickSlot> resetPicks({
  required List<String> reihenfolge,
  required int runden,
  required Map<PickKey, String> rechte,
}) {
  final n = reihenfolge.length;
  return [
    for (var r = 1; r <= runden; r++)
      for (var i = 0; i < n; i++)
        PickSlot(
          runde: r,
          nummerInRunde: i + 1,
          ursprung: reihenfolge[r.isOdd ? i : n - 1 - i],
          besitzer:
              besitzerVon(rechte, r, reihenfolge[r.isOdd ? i : n - 1 - i]),
        ),
  ];
}

/// Die Picks, die [managerId] besitzt — in Draft-Reihenfolge.
List<PickSlot> picksVon(List<PickSlot> alle, String managerId) =>
    [for (final p in alle) if (p.besitzer == managerId) p];

/// Wer im Reset-Draft am Zug ist: der **Besitzer** des Picks. [managers]
/// tragen die Reset-Position als Draft-Position (`managerFuerDraft`). Ist der
/// Besitzer nicht mehr in der Liga, zieht das ursprüngliche Team — dieselbe
/// Regel wie `fantasy_current_manager`.
FantasyManager? amZugMitRechten(
  List<FantasyManager> managers,
  int picksMade,
  Map<PickKey, String> rechte,
) {
  final slotManager = currentManager(managers, picksMade);
  if (slotManager == null || managers.isEmpty) return slotManager;
  final runde = picksMade ~/ managers.length + 1;
  final besitzer = besitzerVon(rechte, runde, slotManager.userId);
  for (final m in managers) {
    if (m.userId == besitzer) return m;
  }
  return slotManager;
}

/// Dürfen in dieser Liga gerade Picks gehandelt werden? Liga mit Reset,
/// erster Draft fertig, Reset noch nicht erfolgt — dieselbe Regel wie
/// `fantasy_picks_handelbar`.
bool picksHandelbar(FantasyLeague league) =>
    league.resetAktiv &&
    league.resetErfolgtAt == null &&
    league.draftStatus == DraftStatus.done;
