/// Offene Beitrittsanfrage an einen öffentlichen Wettbewerb (Fantasy-Liga oder
/// Tipprunde). Trägt nur die Nutzer-ID; Name/Avatar werden über die
/// Profil-Suche nachgeladen (wie im Freunde-System).
class JoinRequest {
  const JoinRequest({required this.userId, required this.createdAt});

  final String userId;
  final DateTime createdAt;

  factory JoinRequest.fromJson(Map<String, dynamic> json) => JoinRequest(
        userId: json['user_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
