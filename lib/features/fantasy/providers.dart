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
import 'data/fantasy_stats_source.dart';
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

/// Alle manuellen Aufstellungen einer Liga in Echtzeit (alle Spieltage).
final leagueLineupsProvider =
    StreamProvider.family<List<FantasyLineup>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).lineupsStream(leagueId);
});

/// Aufstellungs-Deadline (erster Anstoß) eines Spieltags der Saison.
final roundDeadlineProvider =
    FutureProvider.family<DateTime?, int>((ref, round) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyLeagueRepositoryProvider).roundDeadline(season, round);
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
// Scoring (Stats-Feed: serverseitig gespiegelt, Fallback live OpenLigaDB)
// ------------------------------------------------------------------

final roundScoringServiceProvider =
    Provider<RoundScoringService>((ref) => RoundScoringService());

/// Quelle der Roh-Stats: mit Supabase die Tabelle player_match_stats
/// (Quelle der Wahrheit, Schema bereit für Assists/Karten/Minuten), sonst
/// bzw. als Fallback die Live-Berechnung aus OpenLigaDB.
final fantasyStatsSourceProvider = Provider<FantasyStatsSource>((ref) {
  final live = LiveStatsSource(ref.watch(roundScoringServiceProvider));
  return AppConfig.isSupabaseConfigured
      ? DbStatsSource(Supabase.instance.client, live)
      : live;
});

/// Aktueller bzw. letzter Bundesliga-Spieltag (Standard für die Anzeige).
final fantasyCurrentRoundProvider = FutureProvider<int>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return OpenLigaDbProvider().getCurrentRound(Leagues.bundesliga, season);
});

/// Roh-Leistungsdaten aller Poolspieler für einen Spieltag.
final roundStatsProvider =
    FutureProvider.family<Map<String, PlayerMatchStats>, int>((ref, round) async {
  final pool = await ref.watch(playerPoolProvider.future);
  final season = ref.watch(fantasySeasonProvider);
  return ref
      .watch(fantasyStatsSourceProvider)
      .roundStats(pool: pool, season: season, round: round);
});
