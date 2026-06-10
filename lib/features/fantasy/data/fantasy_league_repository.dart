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
        .select('user_id, draft_position, profiles(username)')
        .eq('league_id', leagueId)
        .order('joined_at');
    return rows.map(FantasyManager.fromJson).toList();
  }
}
