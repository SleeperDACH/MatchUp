import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fantasy_models.dart';
import 'fantasy_data_provider.dart';

/// Liest den Spielerpool aus der Supabase-Tabelle `players` (die Quelle
/// der Wahrheit, auf die auch Draft-Picks per FK verweisen). Live-Punkte
/// sind noch nicht angebunden.
class DbFantasyDataProvider implements FantasyDataProvider {
  DbFantasyDataProvider(this._client);

  final SupabaseClient _client;

  @override
  String get id => 'supabase-players';

  @override
  Future<List<FantasyPlayer>> getPlayerPool({required int season}) async {
    final rows = await _client.from('players').select().order('name');
    return rows.map(FantasyPlayer.fromJson).toList();
  }

  @override
  Future<int?> getPlayerPoints({
    required String playerId,
    required int season,
    required int round,
  }) async =>
      null;
}
