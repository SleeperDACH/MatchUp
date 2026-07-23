import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui/app_avatar.dart';
import '../messaging/providers.dart';
import 'data/friends_repository.dart';

final friendsRepositoryProvider = Provider<FriendsRepository>(
    (ref) => FriendsRepository(Supabase.instance.client));

/// Alle eigenen Freundschaften (Echtzeit).
final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  return ref.watch(friendsRepositoryProvider).friendshipsStream();
});

/// Nutzer-IDs der akzeptierten Freunde.
final friendsProvider = Provider<List<String>>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final rows = ref.watch(friendshipsProvider).valueOrNull ?? const [];
  if (me == null) return const [];
  return [for (final f in rows) if (f.accepted) f.otherOf(me)];
});

/// Eingehende, noch offene Freundschaftsanfragen (Absender-IDs).
final incomingRequestsProvider = Provider<List<String>>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final rows = ref.watch(friendshipsProvider).valueOrNull ?? const [];
  if (me == null) return const [];
  return [
    for (final f in rows)
      if (!f.accepted && f.addresseeId == me) f.requesterId
  ];
});

/// Ausgehende, noch offene Freundschaftsanfragen (Empfänger-IDs).
final outgoingRequestsProvider = Provider<List<String>>((ref) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final rows = ref.watch(friendshipsProvider).valueOrNull ?? const [];
  if (me == null) return const [];
  return [
    for (final f in rows)
      if (!f.accepted && f.requesterId == me) f.addresseeId
  ];
});

/// Anzahl offener eingehender Anfragen (für das Tab-Badge).
final incomingRequestsCountProvider = Provider<int>((ref) {
  return ref.watch(incomingRequestsProvider).length;
});

/// Beziehung zu einem bestimmten Nutzer (für den Button auf Profilen).
enum FriendStatus { none, friends, incoming, outgoing }

final friendStatusProvider = Provider.family<FriendStatus, String>((ref, otherId) {
  final me = Supabase.instance.client.auth.currentUser?.id;
  final rows = ref.watch(friendshipsProvider).valueOrNull ?? const [];
  if (me == null) return FriendStatus.none;
  for (final f in rows) {
    if (f.otherOf(me) != otherId) continue;
    if (f.accepted) return FriendStatus.friends;
    return f.requesterId == me ? FriendStatus.outgoing : FriendStatus.incoming;
  }
  return FriendStatus.none;
});

/// Anzeigenamen + Avatare aller beteiligten Nutzer (Freunde + Anfragen).
final _relevantIdsProvider = Provider<Set<String>>((ref) {
  return {
    ...ref.watch(friendsProvider),
    ...ref.watch(incomingRequestsProvider),
    ...ref.watch(outgoingRequestsProvider),
  };
});

final friendNamesProvider = FutureProvider<Map<String, String>>((ref) {
  final ids = ref.watch(_relevantIdsProvider);
  return ref.watch(messagingRepositoryProvider).usernamesFor(ids);
});

final friendAvatarsProvider = FutureProvider<Map<String, AvatarInfo>>((ref) {
  final ids = ref.watch(_relevantIdsProvider);
  return ref.watch(messagingRepositoryProvider).avatarsFor(ids);
});
