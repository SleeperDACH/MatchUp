import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/models.dart';
import '../models/tip_round.dart';

/// Tipprunden-Verwaltung gegen Supabase. RLS sorgt dafür, dass nur die
/// eigenen Runden sichtbar sind.
class TipRoundRepository {
  TipRoundRepository(this._client);

  final SupabaseClient _client;

  Future<List<TipRound>> myRounds() async {
    final rows = await _client
        .from('tip_rounds')
        .select()
        .order('created_at', ascending: false);
    return rows.map(TipRound.fromJson).toList();
  }

  Future<TipRound> createRound({
    required String name,
    required LeagueInfo league,
    required int season,
  }) async {
    final userId = _client.auth.currentUser!.id;
    // Der Trigger tip_rounds_add_creator macht den Ersteller automatisch
    // zum Mitglied.
    final row = await _client
        .from('tip_rounds')
        .insert({
          'name': name.trim(),
          'league_id': league.id,
          'season': season,
          'created_by': userId,
        })
        .select()
        .single();
    return TipRound.fromJson(row);
  }

  Future<TipRound> joinRound(String inviteCode) async {
    final roundId = await _client.rpc<String>(
      'join_tip_round',
      params: {'p_invite_code': inviteCode.trim()},
    );
    final row =
        await _client.from('tip_rounds').select().eq('id', roundId).single();
    return TipRound.fromJson(row);
  }

  Future<List<StandingsEntry>> standings(String roundId) async {
    final rows = await _client
        .from('tip_round_standings')
        .select()
        .eq('round_id', roundId)
        .order('points', ascending: false);
    return rows.map(StandingsEntry.fromJson).toList();
  }
}
