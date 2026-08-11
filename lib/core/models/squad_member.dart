/// Ein Kaderspieler eines Vereins (Sportmonks `/squads/teams/{id}`).
///
/// Bewusst getrennt vom Fantasy-`FantasyPlayer`: Das hier ist der reale Kader
/// zur Anzeige, unabhängig davon, ob der Spieler im Fantasy-Pool steht.
class SquadMember {
  const SquadMember({
    required this.playerId,
    required this.name,
    this.position,
    this.jerseyNumber,
    this.nationality,
    this.dateOfBirth,
    this.imageUrl,
    this.captain = false,
  });

  /// Sportmonks-Spieler-ID (ohne Präfix). Passt zu `players.id` im Pool, das
  /// `sportmonks:<id>` lautet.
  final int playerId;
  final String name;

  /// Englische Sportmonks-Bezeichnung („Goalkeeper", „Defender", …). Die
  /// Übersetzung passiert in der Anzeige, damit hier keine UI-Sprache steckt.
  final String? position;
  final int? jerseyNumber;
  final String? nationality;
  final DateTime? dateOfBirth;
  final String? imageUrl;
  final bool captain;

  /// Alter in Jahren, sofern das Geburtsdatum bekannt ist.
  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var years = now.year - dob.year;
    final hadBirthday =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    if (!hadBirthday) years -= 1;
    return years;
  }

  factory SquadMember.fromJson(Map<String, dynamic> j) {
    final dob = j['date_of_birth'] as String?;
    return SquadMember(
      playerId: (j['player_id'] as num?)?.toInt() ?? 0,
      name: j['name'] as String? ?? '?',
      position: j['position'] as String?,
      jerseyNumber: (j['jersey_number'] as num?)?.toInt(),
      nationality: j['nationality'] as String?,
      dateOfBirth: dob == null ? null : DateTime.tryParse(dob),
      imageUrl: j['image'] as String?,
      captain: j['captain'] as bool? ?? false,
    );
  }
}

/// Gruppierung des Kaders für die Anzeige: Sportmonks-Position → deutsche
/// Bezeichnung. Unbekanntes landet unter „Sonstige", damit niemand aus der
/// Liste fällt.
String squadGroupLabel(String? sportmonksPosition) => switch (
        sportmonksPosition) {
      'Goalkeeper' => 'Torwart',
      'Defender' => 'Abwehr',
      'Midfielder' => 'Mittelfeld',
      'Attacker' || 'Forward' => 'Sturm',
      _ => 'Sonstige',
    };

/// Reihenfolge der Gruppen auf dem Bildschirm.
const squadGroupOrder = ['Torwart', 'Abwehr', 'Mittelfeld', 'Sturm', 'Sonstige'];
