import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/direct_message.dart';

/// Ligaübergreifende Direktnachrichten gegen Supabase. RLS beschränkt Lesen
/// und Senden auf die eigene Beteiligung; Empfänger werden über die
/// öffentliche Profil-Namenssuche gefunden.
class MessagingRepository {
  MessagingRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Alle eigenen Nachrichten (RLS-gefiltert) in Echtzeit, älteste zuerst.
  /// Der Client gruppiert sie zu Konversationen.
  Stream<List<DirectMessage>> messagesStream() => _client
      .from('direct_messages')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((rows) => rows.map(DirectMessage.fromJson).toList());

  Future<void> sendMessage(String recipientId, String body,
      {String? tradeId}) async {
    final uid = _uid;
    if (uid == null) throw StateError('Nicht angemeldet');
    await _client.from('direct_messages').insert({
      'sender_id': uid,
      'recipient_id': recipientId,
      'body': body.trim(),
      'trade_id': ?tradeId,
    });
  }

  /// Nutzer per Benutzername suchen (ohne den eigenen Account).
  Future<List<UserRef>> searchUsers(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    var builder = _client
        .from('profiles')
        .select('id, username')
        .ilike('username', '%$q%');
    final uid = _uid;
    if (uid != null) builder = builder.neq('id', uid);
    final rows = await builder.order('username').limit(20);
    return rows.map(UserRef.fromJson).toList();
  }

  /// Anzeigenamen für eine Menge von Nutzer-IDs (Konversations-Partner).
  Future<Map<String, String>> usernamesFor(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await _client
        .from('profiles')
        .select('id, username')
        .inFilter('id', ids.toList());
    return {
      for (final r in rows) r['id'] as String: r['username'] as String,
    };
  }
}
