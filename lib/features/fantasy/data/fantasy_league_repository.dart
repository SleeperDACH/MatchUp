import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fantasy_models.dart';

/// Fantasy-Liga-Verwaltung gegen Supabase. RLS sorgt dafür, dass nur
/// die eigenen Ligen sichtbar sind.
class FantasyLeagueRepository {
  FantasyLeagueRepository(this._client);

  final SupabaseClient _client;

  Future<List<FantasyLeague>> myLeagues() async {
    final rows = await _client
        .from('fantasy_leagues')
        .select()
        .order('created_at', ascending: false);
    return rows.map(FantasyLeague.fromJson).toList();
  }

  Future<FantasyLeague> createLeague({
    required String name,
    required FantasyMode mode,
    required int season,
    required DraftPickTime pickTime,
    FantasyScoring scoring = FantasyScoring.kickbaseStyle,
    RosterConfig roster = RosterConfig.standard,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('fantasy_leagues')
        .insert({
          'name': name.trim(),
          'mode': mode.name,
          'season': season,
          'draft_pick_seconds': pickTime.seconds,
          'scoring': scoring.toJson(),
          'roster': roster.toJson(),
          'created_by': userId,
        })
        .select()
        .single();
    return FantasyLeague.fromJson(row);
  }

  Future<FantasyLeague> joinLeague(String inviteCode) async {
    final leagueId = await _client.rpc<String>(
      'join_fantasy_league',
      params: {'p_invite_code': inviteCode.trim()},
    );
    final row = await _client
        .from('fantasy_leagues')
        .select()
        .eq('id', leagueId)
        .single();
    return FantasyLeague.fromJson(row);
  }

  Future<List<FantasyManager>> managers(String leagueId) async {
    final rows = await _client
        .from('fantasy_league_members')
        .select('user_id, draft_position, waiver_priority, profiles(username)')
        .eq('league_id', leagueId)
        .order('joined_at');
    return rows.map(FantasyManager.fromJson).toList();
  }

  /// Aktuelle Kader der Liga in Echtzeit (Draft + Free Agency).
  Stream<List<RosterEntry>> rosterStream(String leagueId) => _client
      .from('fantasy_rosters')
      .stream(primaryKey: ['league_id', 'player_id'])
      .eq('league_id', leagueId)
      .map((rows) => rows.map(RosterEntry.fromJson).toList());

  Future<void> dropPlayer(String leagueId, String playerId) => _client.rpc(
        'fantasy_drop_player',
        params: {'p_league_id': leagueId, 'p_player_id': playerId},
      );

  Future<void> addFreeAgent(String leagueId, String addPlayerId,
          {String? dropPlayerId}) =>
      _client.rpc('fantasy_add_free_agent', params: {
        'p_league_id': leagueId,
        'p_add_player_id': addPlayerId,
        'p_drop_player_id': dropPlayerId,
      });

  // ----------------------------------------------------------------
  // Waiver-Wire
  // ----------------------------------------------------------------

  /// Spieler-IDs, die aktuell auf dem Waiver-Wire liegen (claim-only).
  Stream<Set<String>> waiverPlayersStream(String leagueId) => _client
      .from('fantasy_waiver_players')
      .stream(primaryKey: ['league_id', 'player_id'])
      .eq('league_id', leagueId)
      .map((rows) => {
            for (final r in rows)
              if (DateTime.parse(r['clears_at'] as String).isAfter(DateTime.now()))
                r['player_id'] as String
          });

  /// Eigene Waiver-Anträge der Liga in Echtzeit (RLS: nur die eigenen).
  Stream<List<WaiverClaim>> myWaiverClaimsStream(String leagueId) => _client
      .from('fantasy_waiver_claims')
      .stream(primaryKey: ['id'])
      .eq('league_id', leagueId)
      .order('created_at')
      .map((rows) => rows.map(WaiverClaim.fromJson).toList());

  /// Nächste Runde + Waiver-Deadline (2 Tage vor Anstoß). Beide null, wenn
  /// kein Spieltag mehr ansteht.
  Future<({int? round, DateTime? deadline})> waiverWindow(int season) async {
    final res = await _client.rpc(
      'fantasy_next_waiver_window',
      params: {'p_season': season},
    );
    // PostgREST liefert je nach Version ein Objekt oder ein 1-Element-Array.
    final row = res is List
        ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
        : res as Map<String, dynamic>?;
    if (row == null) return (round: null, deadline: null);
    final deadline = row['deadline'];
    return (
      round: row['round'] as int?,
      deadline: deadline == null ? null : DateTime.parse(deadline as String),
    );
  }

  Future<void> submitWaiverClaim(String leagueId, String addPlayerId,
          {String? dropPlayerId, int rank = 1}) =>
      _client.rpc('fantasy_submit_waiver_claim', params: {
        'p_league_id': leagueId,
        'p_add_player_id': addPlayerId,
        'p_drop_player_id': dropPlayerId,
        'p_rank': rank,
      });

  Future<void> cancelWaiverClaim(String claimId) => _client.rpc(
        'fantasy_cancel_waiver_claim',
        params: {'p_claim_id': claimId},
      );
}
