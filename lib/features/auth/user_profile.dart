/// Das eigene Profil inkl. Avatar-Feldern ("Beides kombiniert": Bild-URL
/// oder Emoji + Farbe). Alle Avatar-Felder sind optional.
class UserProfile {
  const UserProfile({
    required this.username,
    this.avatarUrl,
    this.avatarEmoji,
    this.avatarColor,
  });

  final String? username;
  final String? avatarUrl;
  final String? avatarEmoji;
  final String? avatarColor;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        username: json['username'] as String?,
        avatarUrl: json['avatar_url'] as String?,
        avatarEmoji: json['avatar_emoji'] as String?,
        avatarColor: json['avatar_color'] as String?,
      );
}
