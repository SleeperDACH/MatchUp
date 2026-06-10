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

/// Konfigurierbares Punkteschema einer Tipprunde (Kicktipp-Standard:
/// exakt 4, Tordifferenz 3, Tendenz 2). Wird pro Tipprunde gespeichert,
/// damit jede Runde eigene Regeln haben kann — und damit dasselbe System
/// später für andere Sportarten funktioniert.
class ScoringRules {
  const ScoringRules({
    this.exact = 4,
    this.goalDiff = 3,
    this.tendency = 2,
  });

  final int exact;
  final int goalDiff;
  final int tendency;

  static const kicktippDefault = ScoringRules();

  factory ScoringRules.fromJson(Map<String, dynamic> json) => ScoringRules(
        exact: json['exact'] as int? ?? 4,
        goalDiff: json['goalDiff'] as int? ?? 3,
        tendency: json['tendency'] as int? ?? 2,
      );

  Map<String, dynamic> toJson() => {
        'exact': exact,
        'goalDiff': goalDiff,
        'tendency': tendency,
      };
}
