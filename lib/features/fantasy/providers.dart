import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../auth/providers.dart';
import 'data/fantasy_data_provider.dart';
import 'data/fantasy_league_repository.dart';
import 'data/seed_player_pool.dart';
import 'models/fantasy_models.dart';

final fantasyLeagueRepositoryProvider = Provider<FantasyLeagueRepository>(
    (ref) => FantasyLeagueRepository(Supabase.instance.client));

/// Datenquelle für Spielerpool und (später) Live-Punkte. Aktuell der
/// Seed-Pool; ein echter Stats-Adapter wird hier ausgetauscht.
final fantasyDataProvider =
    Provider<FantasyDataProvider>((ref) => const SeedFantasyDataProvider());

/// Startjahr der aktuellen Fantasy-Saison (Bundesliga-Rhythmus).
final fantasySeasonProvider =
    Provider<int>((ref) => Leagues.bundesliga.seasonFor(DateTime.now()));

final myFantasyLeaguesProvider = FutureProvider<List<FantasyLeague>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(const <FantasyLeague>[]);
  return ref.watch(fantasyLeagueRepositoryProvider).myLeagues();
});

final fantasyManagersProvider =
    FutureProvider.family<List<FantasyManager>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).managers(leagueId);
});

final playerPoolProvider = FutureProvider<List<FantasyPlayer>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyDataProvider).getPlayerPool(season: season);
});
