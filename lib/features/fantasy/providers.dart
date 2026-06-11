import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/data/openligadb/openligadb_provider.dart';
import '../../core/models/models.dart';
import '../auth/providers.dart';
import 'data/db_fantasy_data_provider.dart';
import 'data/draft_repository.dart';
import 'data/fantasy_data_provider.dart';
import 'data/fantasy_league_repository.dart';
import 'data/round_scoring_service.dart';
import 'data/seed_player_pool.dart';
import 'logic/fantasy_scoring_engine.dart';
import 'models/fantasy_models.dart';

final fantasyLeagueRepositoryProvider = Provider<FantasyLeagueRepository>(
    (ref) => FantasyLeagueRepository(Supabase.instance.client));

final draftRepositoryProvider =
    Provider<DraftRepository>((ref) => DraftRepository(Supabase.instance.client));

/// Datenquelle für Spielerpool und (später) Live-Punkte. Mit Server der
/// DB-Pool; ohne Konfiguration der Offline-Seed.
final fantasyDataProvider = Provider<FantasyDataProvider>((ref) =>
    AppConfig.isSupabaseConfigured
        ? DbFantasyDataProvider(Supabase.instance.client)
        : const SeedFantasyDataProvider());

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

/// Aktuelle Kader der Liga in Echtzeit (Draft + Free Agency).
final leagueRosterProvider =
    StreamProvider.family<List<RosterEntry>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).rosterStream(leagueId);
});

/// Spieler-IDs auf dem Waiver-Wire (nach Drop claim-only) in Echtzeit.
final waiverPlayersProvider =
    StreamProvider.family<Set<String>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).waiverPlayersStream(leagueId);
});

/// Eigene Waiver-Anträge der Liga in Echtzeit.
final myWaiverClaimsProvider =
    StreamProvider.family<List<WaiverClaim>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).myWaiverClaimsStream(leagueId);
});

/// Nächste Runde + Waiver-Deadline (2 Tage vor Anstoß) der Saison.
final waiverWindowProvider =
    FutureProvider<({int? round, DateTime? deadline})>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyLeagueRepositoryProvider).waiverWindow(season);
});

final playerPoolProvider = FutureProvider<List<FantasyPlayer>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyDataProvider).getPlayerPool(season: season);
});

// ------------------------------------------------------------------
// Draft (Realtime)
// ------------------------------------------------------------------

/// Liga-Zustand in Echtzeit (Draft-Status, Picks, Deadline).
final draftLeagueProvider =
    StreamProvider.family<FantasyLeague?, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).leagueStream(leagueId);
});

/// Alle Picks der Liga in Echtzeit.
final draftPicksProvider =
    StreamProvider.family<List<DraftPick>, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).picksStream(leagueId);
});

// ------------------------------------------------------------------
// Scoring (echte OpenLigaDB-Daten: Tore + Zu-Null)
// ------------------------------------------------------------------

final roundScoringServiceProvider =
    Provider<RoundScoringService>((ref) => RoundScoringService());

/// Aktueller bzw. letzter Bundesliga-Spieltag (Standard für die Anzeige).
final fantasyCurrentRoundProvider = FutureProvider<int>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return OpenLigaDbProvider().getCurrentRound(Leagues.bundesliga, season);
});

/// Roh-Leistungsdaten (Tore/Zu-Null) aller Poolspieler für einen Spieltag.
final roundStatsProvider =
    FutureProvider.family<Map<String, PlayerMatchStats>, int>((ref, round) async {
  final pool = await ref.watch(playerPoolProvider.future);
  final season = ref.watch(fantasySeasonProvider);
  return ref
      .watch(roundScoringServiceProvider)
      .roundStats(pool: pool, season: season, round: round);
});
