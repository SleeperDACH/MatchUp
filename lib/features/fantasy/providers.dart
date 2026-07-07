import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/data/openligadb/openligadb_provider.dart';
import '../../core/models/chat_message.dart';
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
import 'models/trade.dart';

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

/// Verwaiste Teams einer Liga (für die Admin-Zuweisung).
final vacantTeamsProvider =
    FutureProvider.family<List<FantasyManager>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).vacantTeams(leagueId);
});

/// Aktuelle Kader der Liga in Echtzeit (Draft + Free Agency).
final leagueRosterProvider =
    StreamProvider.family<List<RosterEntry>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).rosterStream(leagueId);
});

/// Live-Stream der Chat-Nachrichten einer Fantasy-Liga (älteste zuerst).
final fantasyMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).messageStream(leagueId);
});

/// Trade-Angebote einer Liga (RLS: nur eigene Beteiligung) in Echtzeit.
final leagueTradesProvider =
    StreamProvider.family<List<TradeOffer>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).tradesStream(leagueId);
});

/// Einzelnes Trade-Angebot samt Positionen (für die Chat-Karte).
final tradeDetailProvider = FutureProvider.family<
    ({TradeOffer trade, List<TradeItem> items})?, String>((ref, tradeId) {
  return ref.watch(fantasyLeagueRepositoryProvider).tradeById(tradeId);
});

/// Positionen aller eigenen Trades, gruppiert nach `trade_id` (Echtzeit).
final tradeItemsProvider =
    StreamProvider<Map<String, List<TradeItem>>>((ref) {
  return ref
      .watch(fantasyLeagueRepositoryProvider)
      .tradeItemsStream()
      .map((items) {
    final byTrade = <String, List<TradeItem>>{};
    for (final it in items) {
      byTrade.putIfAbsent(it.tradeId, () => []).add(it);
    }
    return byTrade;
  });
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

/// Vereinslogos (kanonischer Name → Icon-URL) aus der Bundesliga-Tabelle,
/// um bei Spielern das Vereinswappen zu zeigen. Fällt auf die Vorsaison
/// zurück, falls die aktuelle Tabelle noch leer ist (Saisonstart).
final clubIconsProvider = FutureProvider<Map<String, String?>>((ref) async {
  final season = ref.watch(fantasySeasonProvider);
  final provider = OpenLigaDbProvider();
  var rows = await provider.getTable(Leagues.bundesliga, season);
  if (rows.isEmpty) {
    rows = await provider.getTable(Leagues.bundesliga, season - 1);
  }
  return {for (final r in rows) r.team.name: r.team.iconUrl};
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

/// Eigene Draft-Queue (Spieler-IDs nach Rang) in Echtzeit.
final draftQueueProvider =
    StreamProvider.family<List<String>, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).queueStream(leagueId);
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
/// Alle Bundesliga-Fixtures der Fantasy-Saison (Anstoßzeiten, Teams,
/// Ergebnisse) — Basis für die Spieltags-Anzeige und den aktuellen Spieltag.
final fantasySeasonFixturesProvider = FutureProvider<List<Fixture>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return OpenLigaDbProvider().getSeasonFixtures(Leagues.bundesliga, season);
});

/// Aktueller Fantasy-Spieltag: der erste Spieltag, dessen **letzter Anpfiff**
/// noch keine 24 h zurückliegt. Ein beendeter Spieltag bleibt also 24 h nach
/// dem letzten Anpfiff stehen und springt danach auf den nächsten.
final fantasyCurrentRoundProvider = FutureProvider<int>((ref) async {
  final fixtures = await ref.watch(fantasySeasonFixturesProvider.future);
  return currentFantasyRound(fixtures, DateTime.now());
});

/// Pure Regel für [fantasyCurrentRoundProvider] (24 h nach letztem Anpfiff).
int currentFantasyRound(List<Fixture> fixtures, DateTime now) {
  if (fixtures.isEmpty) return 1;
  final lastKick = <int, DateTime>{};
  for (final f in fixtures) {
    final cur = lastKick[f.round];
    if (cur == null || f.kickoff.isAfter(cur)) lastKick[f.round] = f.kickoff;
  }
  final rounds = lastKick.keys.toList()..sort();
  for (final r in rounds) {
    if (now.isBefore(lastKick[r]!.add(const Duration(hours: 24)))) return r;
  }
  return rounds.last; // Saison vorbei → letzter Spieltag.
}

/// Roh-Leistungsdaten aller Poolspieler für einen Spieltag.
final roundStatsProvider =
    FutureProvider.family<Map<String, PlayerMatchStats>, int>((ref, round) async {
  final pool = await ref.watch(playerPoolProvider.future);
  final season = ref.watch(fantasySeasonProvider);
  return ref
      .watch(fantasyStatsSourceProvider)
      .roundStats(pool: pool, season: season, round: round);
});

/// Alle gespielten Spieltage der Saison (Spieltag → Spieler-ID → Stats);
/// Grundlage der Head-to-Head-Bilanz. Leer ohne serverseitige Stats.
final seasonStatsProvider =
    FutureProvider<Map<int, Map<String, PlayerMatchStats>>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyStatsSourceProvider).seasonStats(season: season);
});
