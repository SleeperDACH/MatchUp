import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/messaging_repository.dart';
import 'models/direct_message.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>(
    (ref) => MessagingRepository(Supabase.instance.client));

/// Alle eigenen Direktnachrichten (Echtzeit, älteste zuerst).
final directMessagesProvider = StreamProvider<List<DirectMessage>>((ref) {
  return ref.watch(messagingRepositoryProvider).messagesStream();
});

/// Eine Konversation = Partner-ID + letzte Nachricht, nach Aktualität sortiert.
class Conversation {
  const Conversation({required this.partnerId, required this.lastMessage});
  final String partnerId;
  final DirectMessage lastMessage;
}

/// Konversationsliste aus den eigenen Nachrichten abgeleitet (pro Partner die
/// jeweils letzte Nachricht).
final conversationsProvider = Provider<List<Conversation>>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final msgs = ref.watch(directMessagesProvider).valueOrNull ?? const [];
  if (me == null) return const [];
  final latest = <String, DirectMessage>{};
  for (final m in msgs) {
    final partner = m.partnerOf(me);
    final cur = latest[partner];
    if (cur == null || m.createdAt.isAfter(cur.createdAt)) {
      latest[partner] = m;
    }
  }
  final list = [
    for (final e in latest.entries)
      Conversation(partnerId: e.key, lastMessage: e.value)
  ]..sort((a, b) =>
      b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt));
  return list;
});

/// Anzeigenamen für alle Konversationspartner (für die Liste).
final conversationNamesProvider = FutureProvider<Map<String, String>>((ref) {
  final convos = ref.watch(conversationsProvider);
  final ids = {for (final c in convos) c.partnerId};
  return ref.watch(messagingRepositoryProvider).usernamesFor(ids);
});
