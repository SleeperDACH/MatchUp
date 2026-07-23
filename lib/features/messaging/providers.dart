import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui/app_avatar.dart';
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

/// Profilbilder aller Konversationspartner (für die Liste & den Chatkopf).
final conversationAvatarsProvider =
    FutureProvider<Map<String, AvatarInfo>>((ref) {
  final convos = ref.watch(conversationsProvider);
  final ids = {for (final c in convos) c.partnerId};
  return ref.watch(messagingRepositoryProvider).avatarsFor(ids);
});

/// „Gelesen bis"-Marke je Gesprächspartner (lokal pro Gerät).
final dmLastReadProvider =
    StateNotifierProvider.family<DmReadNotifier, DateTime?, String>(
        (ref, partnerId) => DmReadNotifier(partnerId));

class DmReadNotifier extends StateNotifier<DateTime?> {
  DmReadNotifier(this.partnerId) : super(null) {
    _load();
  }

  final String partnerId;

  String get _key => 'dm_last_read_$partnerId';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s != null) state = DateTime.tryParse(s);
  }

  /// Setzt die Lesemarke; nur vorwärts.
  Future<void> markRead(DateTime at) async {
    if (state != null && !at.isAfter(state!)) return;
    state = at;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, at.toIso8601String());
  }
}

/// Anzahl ungelesener Direktnachrichten (empfangen, neuer als die jeweilige
/// Lesemarke des Partners). Grundlage für die Zahl am Nachrichten-Symbol.
final unreadDmCountProvider = Provider<int>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final msgs = ref.watch(directMessagesProvider).valueOrNull ?? const [];
  if (me == null) return 0;
  var count = 0;
  for (final m in msgs) {
    if (m.senderId == me) continue;
    final lastRead = ref.watch(dmLastReadProvider(m.senderId));
    if (lastRead == null || m.createdAt.isAfter(lastRead)) count++;
  }
  return count;
});

/// Gibt es ungelesene Direktnachrichten (empfangen, neuer als die Lesemarke)?
/// Grundlage für den roten Punkt am Nachrichten-Symbol.
final hasUnreadDmsProvider = Provider<bool>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final msgs = ref.watch(directMessagesProvider).valueOrNull ?? const [];
  if (me == null) return false;
  // Neueste empfangene Nachricht je Partner.
  final latestReceived = <String, DateTime>{};
  for (final m in msgs) {
    if (m.senderId == me) continue;
    final t = latestReceived[m.senderId];
    if (t == null || m.createdAt.isAfter(t)) latestReceived[m.senderId] = m.createdAt;
  }
  for (final e in latestReceived.entries) {
    final lastRead = ref.watch(dmLastReadProvider(e.key));
    if (lastRead == null || e.value.isAfter(lastRead)) return true;
  }
  return false;
});
