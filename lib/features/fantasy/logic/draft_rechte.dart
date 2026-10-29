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
    this.fest = false,
  });

  final int runde;

  /// **Steht die Nummer fest?** Erst mit dem Reset (24.12.) — davor ist sie
  /// eine Hochrechnung aus der aktuellen Tabelle. Gehandelt wird nie die
  /// Nummer, sondern **Runde + ursprüngliches Team**; steigt das Team in der
  /// Tabelle, wandert sein Pick mit (auf Ansage, 21.10.2026). Die Anzeige
  /// nennt deshalb vorher Runde und Team zuerst und die Nummer als „aktuell".
  final bool fest;

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
  bool fest = false,
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
          fest: fest,
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

/// **Wie ein Pick beschriftet wird** (21.10.2026, auf Ansage). Gehandelt wird
/// „Runde 1 von Big Bang", nicht „1.01": Steigt Big Bang in der Tabelle,
/// wandert sein Pick mit. Vor dem Reset steht deshalb Runde und Team vorn und
/// die Nummer als „aktuell …" dahinter; ab dem Reset ist die Nummer fest und
/// steht vorn.
///
/// [team] `null` heißt: der eigene Pick — dann steht nur die Runde da. Ein
/// „eigener" dahinter sagte nichts, was die Liste nicht ohnehin sagt.
({String titel, String? zusatz}) pickBeschriftung({
  required int runde,
  required String? team,
  String? code,
  bool fest = false,
}) {
  final rundeTeam = team == null ? 'Runde $runde' : 'Runde $runde · $team';
  return fest && code != null
      ? (titel: 'Pick $code', zusatz: rundeTeam)
      : (titel: rundeTeam, zusatz: code == null ? null : 'aktuell $code');
}
