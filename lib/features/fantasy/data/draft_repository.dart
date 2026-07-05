import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fantasy_models.dart';

/// Draft-Operationen und Realtime-Streams. Alle schreibenden Aktionen
/// laufen über server-autoritative RPCs (Snake-Reihenfolge, Pickzeit und
/// Auto-Pick werden in der DB erzwungen).
class DraftRepository {
  DraftRepository(this._client);

  final SupabaseClient _client;

  Future<void> startDraft(String leagueId) =>
      _client.rpc('start_fantasy_draft', params: {'p_league_id': leagueId});

  /// Startet den U20-Draft (Dynasty, nach dem Haupt-Draft).
  Future<void> startU20Draft(String leagueId) =>
      _client.rpc('start_u20_draft', params: {'p_league_id': leagueId});

  /// Führt die Dynasty-Liga in die neue Saison: Kader bleibt, Draft-Verlauf
  /// und offene Waiver werden zurückgesetzt. Danach kann der Ersteller den
  /// neuen U20-Draft starten.
  Future<void> rolloverSeason(String leagueId) =>
      _client.rpc('fantasy_rollover_season', params: {'p_league_id': leagueId});

  Future<void> makePick(String leagueId, String playerId) => _client.rpc(
        'fantasy_make_pick',
        params: {'p_league_id': leagueId, 'p_player_id': playerId},
      );

  /// Löst einen Auto-Pick aus, falls die Pickzeit abgelaufen ist oder der
  /// aktuelle Manager abwesend (Auto-Modus) ist. Idempotent (Row-Lock).
  Future<void> autopickIfExpired(String leagueId) => _client.rpc(
        'fantasy_autopick_if_expired',
        params: {'p_league_id': leagueId},
      );

  /// Eigene Draft-Queue (Wunschliste) in Echtzeit, nach Rang sortiert.
  Stream<List<String>> queueStream(String leagueId) => _client
      .from('fantasy_draft_queue')
      .stream(primaryKey: ['league_id', 'manager_id', 'player_id'])
      .eq('league_id', leagueId)
      .order('rank')
      .map((rows) => [for (final r in rows) r['player_id'] as String]);

  /// Ersetzt die eigene Queue durch die übergebene, geordnete Liste.
  Future<void> setQueue(String leagueId, List<String> playerIds) =>
      _client.rpc('fantasy_set_queue',
          params: {'p_league_id': leagueId, 'p_player_ids': playerIds});

  /// Auto-Modus (abwesend) setzen: false beim Betreten, true beim Verlassen
  /// des Draft-Raums.
  Future<void> setAutoPick(String leagueId, bool on) =>
      _client.rpc('fantasy_set_auto_pick',
          params: {'p_league_id': leagueId, 'p_on': on});

  /// Liga-Zustand in Echtzeit (Draft-Status, picks_made, Deadline).
  Stream<FantasyLeague?> leagueStream(String leagueId) => _client
      .from('fantasy_leagues')
      .stream(primaryKey: ['id'])
      .eq('id', leagueId)
      .map((rows) => rows.isEmpty ? null : FantasyLeague.fromJson(rows.first));

  /// Alle Picks der Liga in Echtzeit, nach Pick-Nummer sortiert.
  Stream<List<DraftPick>> picksStream(String leagueId) => _client
      .from('draft_picks')
      .stream(primaryKey: ['league_id', 'pick_number'])
      .eq('league_id', leagueId)
      .map((rows) => (rows.map(DraftPick.fromJson).toList())
        ..sort((a, b) => a.phase == b.phase
            ? a.pickNumber.compareTo(b.pickNumber)
            : a.phase.index.compareTo(b.phase.index)));
}
