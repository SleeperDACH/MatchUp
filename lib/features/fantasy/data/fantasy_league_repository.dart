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

  /// Löscht eine Fantasy-Liga endgültig (nur Ersteller, per RLS). Abhängige
  /// Daten (Mitglieder, Kader, Lineups, Waiver, Draft) gehen per Cascade mit.
  Future<void> deleteLeague(String leagueId) =>
      _client.from('fantasy_leagues').delete().eq('id', leagueId);

  /// Ändert die Pickzeit nachträglich — nur vor dem Draft (Status `setup`).
  /// RLS erlaubt das Update nur dem Ersteller.
  Future<void> updatePickTime(String leagueId, DraftPickTime pickTime) =>
      _client
          .from('fantasy_leagues')
          .update({'draft_pick_seconds': pickTime.seconds})
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Draft-Einstellungen (Pickzeit, Runden über die roster-JSONB,
  /// Slow-Draft-Pause) — nur vor dem Draft (`.eq('draft_status','setup')`
  /// erzwingt das serverseitig; RLS erlaubt es nur dem Ersteller).
  Future<void> updateDraftSettings(
    String leagueId, {
    required DraftPickTime pickTime,
    required RosterConfig roster,
    required int? pauseStart,
    required int? pauseEnd,
    required String orderMode,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({
            'draft_pick_seconds': pickTime.seconds,
            'roster': roster.toJson(),
            'draft_pause_start': pauseStart,
            'draft_pause_end': pauseEnd,
            'draft_order_mode': orderMode,
          })
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Manuelle Draft-Reihenfolge setzen (Ersteller, nur im Setup). Die
  /// Positionen ergeben sich aus der Reihenfolge von [orderedUserIds].
  Future<void> setDraftOrder(String leagueId, List<String> orderedUserIds) =>
      _client.rpc('set_fantasy_draft_order', params: {
        'p_league_id': leagueId,
        'p_user_ids': orderedUserIds,
      });

  /// Liga-Einstellungen (Teilnehmer-Limit) — ebenfalls nur vor dem Draft.
  Future<void> updateLeagueSettings(
    String leagueId, {
    required int? maxTeams,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({'max_teams': maxTeams})
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Playoff-Einstellungen (Teams, Wochen je Runde, Trade-Deadline-Offset) —
  /// nur vor dem Draft.
  Future<void> updatePlayoffSettings(
    String leagueId, {
    required int teams,
    required int weeks,
    required int tradeDeadlineOffset,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({
            'playoff_teams': teams,
            'playoff_weeks': weeks,
            'trade_deadline_offset': tradeDeadlineOffset,
          })
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

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

  // ----------------------------------------------------------------
  // Manuelle Aufstellung
  // ----------------------------------------------------------------

  /// Alle Aufstellungen der Liga in Echtzeit (für „Mein Team" & Tabelle);
  /// nach Spieltag wird im Client gefiltert.
  Stream<List<FantasyLineup>> lineupsStream(String leagueId) => _client
      .from('fantasy_lineups')
      .stream(primaryKey: ['league_id', 'manager_id', 'season', 'round'])
      .eq('league_id', leagueId)
      .map((rows) => rows.map(FantasyLineup.fromJson).toList());

  /// Aufstellungs-Deadline (erster Anstoß des Spieltags); null, wenn der
  /// Spieltag (noch) nicht in den gespiegelten Fixtures liegt.
  Future<DateTime?> roundDeadline(int season, int round) async {
    final ts = await _client.rpc<String?>('fantasy_round_deadline',
        params: {'p_season': season, 'p_round': round});
    return ts == null ? null : DateTime.parse(ts);
  }

  Future<void> setLineup(String leagueId, int round, List<String> playerIds) =>
      _client.rpc('fantasy_set_lineup', params: {
        'p_league_id': leagueId,
        'p_round': round,
        'p_player_ids': playerIds,
      });
}
