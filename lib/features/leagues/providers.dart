import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/ui/app_avatar.dart';
import '../fantasy/providers.dart';
import '../messaging/providers.dart';
import '../tippspiel/providers.dart';
import 'data/leagues_repository.dart';
import 'models/join_request.dart';
import 'models/public_league_result.dart';

final leaguesRepositoryProvider = Provider<LeaguesRepository>(
    (ref) => LeaguesRepository(Supabase.instance.client));

/// Ergebnisse der öffentlichen Ligasuche zu einer (getrimmten) Suchanfrage.
final publicLeagueSearchProvider =
    FutureProvider.family<List<PublicLeagueResult>, String>((ref, query) {
  return ref.watch(leaguesRepositoryProvider).search(query);
});

/// Offene Beitrittsanfragen einer Fantasy-Liga (nur Admin sieht Daten, live).
final fantasyJoinRequestsProvider =
    StreamProvider.family<List<JoinRequest>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).pendingRequests(leagueId);
});

/// Offene Beitrittsanfragen einer Tipprunde (nur Admin sieht Daten, live).
final tipJoinRequestsProvider =
    StreamProvider.family<List<JoinRequest>, String>((ref, roundId) {
  return ref.watch(tipRoundRepositoryProvider).pendingRequests(roundId);
});

/// Anzeigenamen + Avatare zu einer Menge Nutzer-IDs (für die Anfragen-Liste).
/// Gekeyt per komma-separierter, sortierter ID-Liste, damit sich die Future
/// nur bei geänderter ID-Menge neu bildet (kein Flackern bei Stream-Updates).
typedef ProfileLookup = ({
  Map<String, String> names,
  Map<String, AvatarInfo> avatars
});

final joinRequestProfilesProvider =
    FutureProvider.family<ProfileLookup, String>((ref, idsCsv) async {
  final ids = idsCsv.isEmpty ? <String>{} : idsCsv.split(',').toSet();
  final repo = ref.watch(messagingRepositoryProvider);
  final names = await repo.usernamesFor(ids);
  final avatars = await repo.avatarsFor(ids);
  return (names: names, avatars: avatars);
});
