/// Verfügbare Bonustipp-Fragen: (Schlüssel, Anzeigename, max. Teams), in
/// fester Reihenfolge. Genutzt vom Erstellen-Screen (Auswahl) und der Abgabe.
/// „Absteiger" erlaubt zwei Teams, alle anderen genau eines.
const bonusTipQuestions = <(String, String, int)>[
  ('meister', 'Meister', 1),
  ('absteiger', 'Absteiger', 2),
  ('torschuetzenkoenig_team', 'Team des Torschützenkönigs', 1),
  ('trainerentlassung', 'Erste Trainerentlassung', 1),
];

/// Anzeigename zu einem Bonustipp-Schlüssel.
String bonusTipLabel(String key) => bonusTipQuestions
    .firstWhere((q) => q.$1 == key, orElse: () => (key, key, 1))
    .$2;

/// Maximale Anzahl Teams für eine Bonustipp-Frage (Absteiger: 2, sonst 1).
int bonusTipMax(String key) => bonusTipQuestions
    .firstWhere((q) => q.$1 == key, orElse: () => (key, key, 1))
    .$3;

/// Eine abgegebene Bonustipp-Antwort eines Mitglieds (ein Team je Frage).
class BonusAnswer {
  const BonusAnswer({
    required this.userId,
    required this.question,
    required this.teamId,
    required this.teamName,
  });

  final String userId;
  final String question;
  final String teamId;
  final String teamName;

  factory BonusAnswer.fromJson(Map<String, dynamic> json) => BonusAnswer(
        userId: json['user_id'] as String,
        question: json['question'] as String,
        teamId: json['team_id'] as String,
        teamName: json['team_name'] as String,
      );
}

/// Ein abgegebener Tipp für ein Spiel.
class Tip {
  const Tip({
    required this.fixtureId,
    required this.homeGoals,
    required this.awayGoals,
  });

  final String fixtureId;
  final int homeGoals;
  final int awayGoals;

  factory Tip.fromJson(Map<String, dynamic> json) => Tip(
        fixtureId: json['fixtureId'] as String,
        homeGoals: json['homeGoals'] as int,
        awayGoals: json['awayGoals'] as int,
      );

  Map<String, dynamic> toJson() => {
        'fixtureId': fixtureId,
        'homeGoals': homeGoals,
        'awayGoals': awayGoals,
      };
}

/// Konfigurierbares Punkteschema **und** Modi einer Tipprunde. Basiswertung
/// nach Kicktipp-Standard (exakt 4, Tordifferenz 3, Tendenz 2); dazu die vom
/// Ersteller frei kombinierbaren Zusatz-Modi. Wird pro Tipprunde als JSONB
/// gespeichert — jede Runde kann eigene Regeln haben, und dasselbe System
/// funktioniert später für andere Sportarten.
///
/// Modi (alle unabhängig kombinierbar):
/// - [oddsBonus]: Quoten-/Außenseiter-Bonus. Zwei konfigurierbare Stufen:
///   ab Quote [oddsOdds1] gibt es [oddsPoints1], ab der höheren Quote
///   [oddsOdds2] gibt es [oddsPoints2] (nicht stapelnd). Default **aus** —
///   den Bonus gibt es nur, wenn er beim Erstellen aktiv gewählt wurde.
/// - [solo]: Alleinstellungs-Bonus in Punkten; wer als Einzige/r das exakte
///   Ergebnis eines Spiels trifft, bekommt diese Punkte on top. `0` = aus.
/// - [headToHead]: Duell-Modus (jeder Spieltag als 1-gegen-1). Reine Anzeige,
///   ändert die Punktewertung nicht (kein View-Eingriff).
/// - [bonusTips]: aktivierte Bonustipp-Fragen (Saison-Prognosen, Schlüssel
///   z. B. `meister`, `absteiger`, `torschuetzenkoenig_team`,
///   `trainerentlassung`). Leer = Modus aus.
///
/// **Achtung:** Punktewirksame Felder ([exact], [goalDiff], [tendency],
/// [oddsBonus] samt Stufen, [solo]) existieren gespiegelt in der SQL-View
/// `tip_round_standings` — bei Änderungen beide anpassen.
class ScoringRules {
  const ScoringRules({
    this.exact = 4,
    this.goalDiff = 3,
    this.tendency = 2,
    this.wrongTip = 0,
    this.oddsBonus = false,
    this.oddsOdds1 = 3.0,
    this.oddsPoints1 = 1,
    this.oddsOdds2 = 5.0,
    this.oddsPoints2 = 5,
    this.solo = 0,
    this.headToHead = false,
    this.bonusTips = const [],
    this.bonusPoints = 5,
  });

  final int exact;
  final int goalDiff;
  final int tendency;

  /// Punkte für einen komplett falschen Tipp (falsche Tendenz). Standard 0,
  /// als Strafe bis −5 einstellbar.
  final int wrongTip;

  /// Quoten-/Außenseiter-Bonus aktiv.
  final bool oddsBonus;

  /// Stufe 1 (moderater Außenseiter): ab dieser Quote gibt es [oddsPoints1].
  final double oddsOdds1;
  final int oddsPoints1;

  /// Stufe 2 (krasser Außenseiter): ab dieser (höheren) Quote gibt es
  /// [oddsPoints2]. Nicht stapelnd — die höhere Stufe gewinnt.
  final double oddsOdds2;
  final int oddsPoints2;

  /// Alleinstellungs-Bonus in Punkten (0 = aus).
  final int solo;

  /// Head-to-Head-Modus (Spieltag = Duelle). Reine Anzeige.
  final bool headToHead;

  /// Aktivierte Bonustipp-Fragen (leer = Modus aus).
  final List<String> bonusTips;

  /// Punkte je korrekt getippter Bonustipp-Frage.
  final int bonusPoints;

  static const kicktippDefault = ScoringRules();

  factory ScoringRules.fromJson(Map<String, dynamic> json) => ScoringRules(
        exact: json['exact'] as int? ?? 4,
        goalDiff: json['goalDiff'] as int? ?? 3,
        tendency: json['tendency'] as int? ?? 2,
        wrongTip: json['wrongTip'] as int? ?? 0,
        oddsBonus: json['oddsBonus'] as bool? ?? false,
        oddsOdds1: (json['oddsOdds1'] as num?)?.toDouble() ?? 3.0,
        oddsPoints1: json['oddsPoints1'] as int? ?? 1,
        oddsOdds2: (json['oddsOdds2'] as num?)?.toDouble() ?? 5.0,
        oddsPoints2: json['oddsPoints2'] as int? ?? 5,
        solo: json['solo'] as int? ?? 0,
        headToHead: json['headToHead'] as bool? ?? false,
        bonusTips:
            (json['bonusTips'] as List?)?.map((e) => e as String).toList() ??
                const [],
        bonusPoints: json['bonusPoints'] as int? ?? 5,
      );

  Map<String, dynamic> toJson() => {
        'exact': exact,
        'goalDiff': goalDiff,
        'tendency': tendency,
        'wrongTip': wrongTip,
        'oddsBonus': oddsBonus,
        'oddsOdds1': oddsOdds1,
        'oddsPoints1': oddsPoints1,
        'oddsOdds2': oddsOdds2,
        'oddsPoints2': oddsPoints2,
        'solo': solo,
        'headToHead': headToHead,
        'bonusTips': bonusTips,
        'bonusPoints': bonusPoints,
      };
}
