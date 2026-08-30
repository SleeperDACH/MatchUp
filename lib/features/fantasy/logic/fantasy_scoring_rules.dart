/// Die maßgebliche Fantasy-Punktevergabe als Daten.
///
/// Spiegelt `scoring/config/scoring.config.json` — **beide müssen gleich
/// bleiben**. Das TypeScript-Modul unter `scoring/` ist die Referenz für
/// Balance-Simulationen, diese Datei ist dieselbe Wertung für die App. Wer
/// einen Punktwert ändert, ändert ihn an beiden Stellen (wie bei
/// `tip_scoring.dart` ↔ SQL-View `tip_round_standings`).
///
/// Keine Magic Numbers im Rechenweg: Alle Werte, Schwellen und Beschriftungen
/// stehen hier; `scoreFantasyPlayer` liest ausschließlich daraus.
library;

import '../models/fantasy_models.dart' show PlayerPosition;

/// Eine Einsatz-Stufe: ab [atLeastMinutes] gibt es [points].
class AppearanceTier {
  const AppearanceTier(this.atLeastMinutes, this.points, this.label);
  final int atLeastMinutes;
  final double points;
  final String label;
}

/// Eine Meilenstein-Schwelle: ab [atLeast] Aktionen gibt es [bonus] obendrauf.
/// Die Boni sind **kumulativ** — wer die höhere Schwelle reißt, bekommt die
/// darunterliegenden mit.
class Milestone {
  const Milestone(this.atLeast, this.bonus);
  final int atLeast;
  final double bonus;
}

/// Punktwert, der je nach Position unterschiedlich ausfällt.
class ByPosition {
  const ByPosition({
    required this.gk,
    required this.def,
    required this.mid,
    required this.fwd,
  });

  /// Für Werte, die für alle Positionen gleich sind.
  const ByPosition.flat(double v) : gk = v, def = v, mid = v, fwd = v;

  final double gk;
  final double def;
  final double mid;
  final double fwd;

  double of(PlayerPosition p) => switch (p) {
        PlayerPosition.gk => gk,
        PlayerPosition.def => def,
        PlayerPosition.mid => mid,
        PlayerPosition.fwd => fwd,
      };
}

/// Vollständige Punktevergabe. Die Vorgabe [standard] ist die verbindliche
/// Wertung aus `scoring.config.json`.
class FantasyScoringRules {
  const FantasyScoringRules({
    this.appearance = const [
      AppearanceTier(90, 10, 'Einsatz (90 Min)'),
      AppearanceTier(60, 6, 'Einsatz (60–89 Min)'),
      AppearanceTier(30, 4, 'Einsatz (30–59 Min)'),
      AppearanceTier(1, 2, 'Einsatz (1–29 Min)'),
    ],
    this.goal = 15,
    this.penaltyGoal = 12,
    this.assist = 10,
    this.bigChanceCreated = 6,
    this.keyPass = 1.5,
    this.shotOnTarget = 2,
    this.successfulDribble = 1,
    this.cleanSheetMinMinutes = 60,
    // **Das Mittelfeld bekommt 4 für die Null hinten.** Vorher ging es leer
    // aus, obwohl ein defensiver Sechser sie mit erarbeitet — gemessen kam
    // das Mittelfeld auf 13,7 Punkte im Schnitt gegen 15,1 im Sturm, bei
    // seltener Torbeteiligung (0,040 Tore je Einsatz gegenüber 0,069 in der
    // Abwehr). Vier statt zwölf, weil es seine Hauptaufgabe nicht ist.
    this.cleanSheet = const ByPosition(gk: 12, def: 12, mid: 4, fwd: 0),
    this.goalConceded = const ByPosition(gk: -4, def: -4, mid: 0, fwd: 0),
    this.save = 3,
    this.penaltySaved = 12,
    this.tackleWon = const ByPosition.flat(1),
    this.interception = const ByPosition.flat(1),
    this.ballRecovery = const ByPosition.flat(0.4),
    this.clearance = const ByPosition.flat(0.4),
    this.blockedShot = const ByPosition.flat(1),
    this.passMilestones = const {
      PlayerPosition.gk: [Milestone(25, 3), Milestone(35, 3)],
      PlayerPosition.def: [Milestone(45, 3), Milestone(70, 3)],
      // **30/45 statt 40/60.** Die alten Schwellen lagen über dem, was ein
      // Mittelfeldspieler tatsächlich spielt: gemessener Median 28 genaue
      // Pässe, oberes Viertel 37 — die Vierzig erreichte fast niemand, der
      // Bonus war praktisch tot.
      PlayerPosition.mid: [Milestone(30, 3), Milestone(45, 3)],
      PlayerPosition.fwd: [Milestone(20, 3), Milestone(30, 3)],
    },
    this.saveMilestones = const [Milestone(5, 8), Milestone(8, 12)],
    this.defensiveMilestones = const {
      PlayerPosition.gk: [Milestone(9, 6), Milestone(14, 6), Milestone(19, 6)],
      PlayerPosition.def: [Milestone(9, 6), Milestone(14, 6), Milestone(19, 6)],
      PlayerPosition.mid: [Milestone(10, 6), Milestone(14, 6)],
      PlayerPosition.fwd: [Milestone(8, 6), Milestone(12, 6)],
    },
    this.yellowCard = -4,
    this.secondYellow = -6,
    this.redCard = -10,
    this.ownGoal = -12,
    this.penaltyMissed = -8,
    this.errorLeadToGoal = -6,
    this.bigChanceMissed = -4,
    this.offside = -1,
    this.foul = -0.4,
    this.possessionLost = -0.4,
    this.ratingTiers = const [
      (9.0, 10.0),
      (8.0, 6.0),
      (7.0, 3.0),
      (6.0, 0.0),
      (5.0, -3.0),
      (0.0, -6.0),
    ],
  });

  final List<AppearanceTier> appearance;

  // Offensive
  final double goal;
  final double penaltyGoal;
  final double assist;
  final double bigChanceCreated;
  final double keyPass;
  final double shotOnTarget;
  final double successfulDribble;

  // Defensive
  final int cleanSheetMinMinutes;
  final ByPosition cleanSheet;
  final ByPosition goalConceded;
  final double save;
  final double penaltySaved;
  final ByPosition tackleWon;
  /// Abgefangener Ball (`interceptions`).
  final ByPosition interception;

  /// **Balleroberung** (`ball-recovery`) — ein anderes Feld als
  /// [interception] und rund viermal häufiger (Schnitt 2,9 gegen 0,8
  /// je Spieler ab 60 Minuten). Deshalb der Wert einer Klärung, nicht
  /// der eines Zweikampfs.
  ///
  /// Zählt **nicht** in [defensiveMilestones]: Deren Schwellen sind ohne
  /// dieses Feld geeicht, und mit ihm spränge der Median beim Torwart
  /// von 0 auf 8 — direkt an die erste Schwelle.
  final ByPosition ballRecovery;
  final ByPosition clearance;
  final ByPosition blockedShot;

  // Meilensteine

  /// **Genaue Pässe**, positionsabhängig — der teuerste Teil dieser Wertung,
  /// wenn man ihn falsch baut.
  ///
  /// Ein Wert *je Pass* schied aus: Ein Mittelfeldspieler kommt auf Dutzende,
  /// ein Stürmer auf eine Handvoll. Der Einzelwert müsste so klein sein, dass
  /// er in der Anzeige verschwindet — und er belohnte die Position, nicht die
  /// Leistung.
  ///
  /// Die Schwellen sind an echten Daten gemessen (vier Partien, nur Spieler ab
  /// 60 Minuten): Median/oberes Viertel lagen bei TW 25/29, ABW 34/53,
  /// MF 28/37, ST 14/15. Sie liegen deshalb je Position anders — 30 genaue
  /// Pässe sind für einen Stürmer herausragend und für einen Verteidiger
  /// unterdurchschnittlich.
  final Map<PlayerPosition, List<Milestone>> passMilestones;

  final List<Milestone> saveMilestones;
  final Map<PlayerPosition, List<Milestone>> defensiveMilestones;

  // Negativ
  final double yellowCard;
  final double secondYellow;
  final double redCard;
  final double ownGoal;
  final double penaltyMissed;
  final double errorLeadToGoal;
  final double bigChanceMissed;
  final double offside;
  final double foul;
  final double possessionLost;

  /// Rating-Stufen als (Mindest-Rating, Punkte), absteigend geordnet.
  final List<(double, double)> ratingTiers;

  /// Die verbindliche Wertung.
  static const standard = FantasyScoringRules();

  /// Aus der pro Liga gespeicherten JSONB-Spalte.
  ///
  /// Ligen, die vor der Umstellung angelegt wurden, tragen dort noch das alte
  /// 6-Kategorien-Objekt ohne `version`. Diese Werte in die neue Wertung zu
  /// übernehmen wäre falsch — ein „goalMid: 5" aus dem alten Modell hat mit
  /// den 16 Punkten dieser Wertung nichts zu tun. Solche Ligen bekommen
  /// deshalb die Standardwertung.
  factory FantasyScoringRules.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2) return standard;
    double d(String k, double fallback) =>
        (json[k] as num?)?.toDouble() ?? fallback;
    const s = standard;
    return FantasyScoringRules(
      goal: d('goal', s.goal),
      penaltyGoal: d('penaltyGoal', s.penaltyGoal),
      assist: d('assist', s.assist),
      bigChanceCreated: d('bigChanceCreated', s.bigChanceCreated),
      keyPass: d('keyPass', s.keyPass),
      shotOnTarget: d('shotOnTarget', s.shotOnTarget),
      successfulDribble: d('successfulDribble', s.successfulDribble),
      save: d('save', s.save),
      penaltySaved: d('penaltySaved', s.penaltySaved),
      yellowCard: d('yellowCard', s.yellowCard),
      secondYellow: d('secondYellow', s.secondYellow),
      redCard: d('redCard', s.redCard),
      ownGoal: d('ownGoal', s.ownGoal),
      penaltyMissed: d('penaltyMissed', s.penaltyMissed),
      errorLeadToGoal: d('errorLeadToGoal', s.errorLeadToGoal),
      bigChanceMissed: d('bigChanceMissed', s.bigChanceMissed),
      offside: d('offside', s.offside),
      foul: d('foul', s.foul),
      possessionLost: d('possessionLost', s.possessionLost),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 2,
        'goal': goal,
        'penaltyGoal': penaltyGoal,
        'assist': assist,
        'bigChanceCreated': bigChanceCreated,
        'keyPass': keyPass,
        'shotOnTarget': shotOnTarget,
        'successfulDribble': successfulDribble,
        'save': save,
        'penaltySaved': penaltySaved,
        'yellowCard': yellowCard,
        'secondYellow': secondYellow,
        'redCard': redCard,
        'ownGoal': ownGoal,
        'penaltyMissed': penaltyMissed,
        'errorLeadToGoal': errorLeadToGoal,
        'bigChanceMissed': bigChanceMissed,
        'offside': offside,
        'foul': foul,
        'possessionLost': possessionLost,
      };
}
