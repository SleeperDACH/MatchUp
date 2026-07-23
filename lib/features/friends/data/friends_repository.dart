import 'package:supabase_flutter/supabase_flutter.dart';

/// Eine Freundschafts-Zeile aus `public.friendships`.
class Friendship {
  const Friendship({
    required this.requesterId,
    required this.addresseeId,
    required this.accepted,
  });

  final String requesterId;
  final String addresseeId;
  final bool accepted;

  /// Die andere Partei aus Sicht von [me].
  String otherOf(String me) => requesterId == me ? addresseeId : requesterId;

  factory Friendship.fromJson(Map<String, dynamic> j) => Friendship(
        requesterId: j['requester_id'] as String,
        addresseeId: j['addressee_id'] as String,
        accepted: (j['status'] as String?) == 'accepted',
      );
}

/// Freundschaften gegen Supabase. RLS beschränkt Lesen/Ändern auf die eigene
/// Beteiligung; Nutzer werden über die öffentliche Profil-Namenssuche gefunden.
class FriendsRepository {
  FriendsRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Alle eigenen Freundschaften (RLS-gefiltert) in Echtzeit.
  Stream<List<Friendship>> friendshipsStream() => _client
      .from('friendships')
      .stream(primaryKey: ['requester_id', 'addressee_id'])
      .map((rows) => rows.map(Friendship.fromJson).toList());

  /// Freundschaftsanfrage an [addresseeId] stellen.
  Future<void> sendRequest(String addresseeId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Nicht angemeldet');
    await _client.from('friendships').insert({
      'requester_id': uid,
      'addressee_id': addresseeId,
      'status': 'pending',
    });
  }

  /// Eingehende Anfrage von [requesterId] annehmen.
  Future<void> accept(String requesterId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Nicht angemeldet');
    await _client
        .from('friendships')
        .update({'status': 'accepted'})
        .match({'requester_id': requesterId, 'addressee_id': uid});
  }

  /// Freundschaft/Anfrage mit [otherId] entfernen (in beide Richtungen).
  Future<void> remove(String otherId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Nicht angemeldet');
    await _client.from('friendships').delete().or(
          'and(requester_id.eq.$uid,addressee_id.eq.$otherId),'
          'and(requester_id.eq.$otherId,addressee_id.eq.$uid)',
        );
  }
}
