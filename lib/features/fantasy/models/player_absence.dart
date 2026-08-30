/// **Ein Ausfall: verletzt oder gesperrt.**
///
/// Quelle ist Sportmonks (`include=sidelined`), gespiegelt von
/// `sync-absences`. Gelesen wird über die Sicht `player_absences_v`, die
/// überholte Einträge kennzeichnet — die Quelle führt Spieler teils
/// jahrelang als ausgefallen, obwohl sie längst wieder spielen.
class PlayerAbsence {
  const PlayerAbsence({
    required this.playerId,
    required this.gesperrt,
    this.grundQuelle,
    this.seit,
    this.spieleVerpasst,
  });

  final String playerId;

  /// `true` = Sperre, `false` = Verletzung. Zwei Zustände, zwei Symbole: Eine
  /// Sperre ist eine Folge des eigenen Verhaltens und endet an einem
  /// bekannten Tag, eine Verletzung nicht.
  final bool gesperrt;

  /// Der Grund im Wortlaut der Quelle, englisch („Hamstring Injury").
  /// [grund] übersetzt ihn, soweit er bekannt ist.
  final String? grundQuelle;

  final DateTime? seit;
  final int? spieleVerpasst;

  factory PlayerAbsence.fromJson(Map<String, dynamic> j) => PlayerAbsence(
        playerId: j['player_id'] as String,
        gesperrt: (j['kategorie'] as String?) == 'suspended',
        grundQuelle: j['grund_quelle'] as String?,
        seit: DateTime.tryParse((j['seit'] as String?) ?? ''),
        spieleVerpasst: (j['spiele_verpasst'] as num?)?.toInt(),
      );

  /// Der Grund auf Deutsch.
  ///
  /// **Die Liste ist gemessen, nicht geraten**: Sie enthält genau die 35
  /// Gründe, die am 30.08.2026 in der Liga tatsächlich vorkamen. Ein
  /// unbekannter Grund fällt auf den englischen Wortlaut zurück — eine
  /// Auskunft in der falschen Sprache ist besser als keine, und „Verletzung"
  /// für alles wäre der Verlust genau der Information, für die es den Eintrag
  /// gibt.
  String get grund {
    final q = grundQuelle;
    if (q == null || q.isEmpty) return gesperrt ? 'Sperre' : 'Verletzung';
    return _deutsch[q] ?? q;
  }

  static const _deutsch = <String, String>{
    'Achilles tendon problems': 'Achillessehnen-Probleme',
    'Achilles tendon rupture': 'Achillessehnenriss',
    'Adductor Injury': 'Adduktorenverletzung',
    'Adductor Pain': 'Adduktorenbeschwerden',
    'Ankle Injury': 'Sprunggelenkverletzung',
    'Back Problems': 'Rückenprobleme',
    'Bruised Ribs': 'Rippenprellung',
    'Cruciate Ligament Tear': 'Kreuzbandriss',
    'Fitness': 'Aufbautraining',
    'Food Poisoning': 'Lebensmittelvergiftung',
    'Foot Bruise': 'Fußprellung',
    'Foot Injury': 'Fußverletzung',
    'Groin Problems': 'Leistenprobleme',
    'Hamstring Injury': 'Verletzung der hinteren Oberschenkelmuskulatur',
    'Hip Injury': 'Hüftverletzung',
    'Ill': 'Erkrankung',
    'Indirect Card Suspension': 'Gelbsperre',
    'Infection': 'Infekt',
    'Inner Knee Ligament Tear': 'Innenbandriss im Knie',
    'Inner Ligament Injury': 'Innenbandverletzung',
    'Inner Ligament Tear In Ankle Joint': 'Innenbandriss im Sprunggelenk',
    'Knee Injury': 'Knieverletzung',
    'Knee Problems': 'Knieprobleme',
    'Knock': 'Prellung',
    'Muscle Injury': 'Muskelverletzung',
    'Muscular problems': 'Muskuläre Probleme',
    'Outer Ligament Problems': 'Außenbandprobleme',
    'Patellar Tendon Problems': 'Patellasehnen-Probleme',
    'Red Card Suspension': 'Rotsperre',
    'Shoulder Injury': 'Schulterverletzung',
    'Syndesmosis Ligament Tear': 'Syndesmosebandriss',
    'Thigh Problems': 'Oberschenkelprobleme',
    'Tibia And Fibula Fracture': 'Schien- und Wadenbeinbruch',
    'Toe Injury': 'Zehenverletzung',
    'Unknown Injury': 'Verletzung ohne nähere Angabe',
  };
}
