import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/public_league_result.dart';

/// Suche über öffentliche Wettbewerbe (Fantasy-Ligen + Tipprunden). Läuft über
/// die security-definer-RPC `search_public_leagues`, damit keine internen
/// Felder (Einladungscode, Scoring) an Nicht-Mitglieder geraten.
class LeaguesRepository {
  LeaguesRepository(this._client);

  final SupabaseClient _client;

  Future<List<PublicLeagueResult>> search(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_public_leagues',
      params: {'p_query': query.trim()},
    );
    return rows
        .map((r) => PublicLeagueResult.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
