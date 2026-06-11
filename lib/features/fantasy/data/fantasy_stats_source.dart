import 'package:supabase_flutter/supabase_flutter.dart';

import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import 'round_scoring_service.dart';

/// Quelle der Roh-Leistungsdaten (Tore, Assists, Karten, Minuten, Zu-Null)
/// je Spieltag — anbieter-neutral. So lässt sich die OpenLigaDB-Ableitung
/// gegen einen vollständigen Feed tauschen, ohne Scoring/UI anzufassen.
abstract class FantasyStatsSource {
  Future<Map<String, PlayerMatchStats>> roundStats({
    required List<FantasyPlayer> pool,
    required int season,
    required int round,
  });
}

/// Live aus OpenLigaDB berechnet (Tore + Zu-Null). Quelle im lokalen Modus
/// und Fallback, solange ein Spieltag serverseitig nicht gespiegelt ist.
class LiveStatsSource implements FantasyStatsSource {
  LiveStatsSource(this._service);

  final RoundScoringService _service;

  @override
  Future<Map<String, PlayerMatchStats>> roundStats({
    required List<FantasyPlayer> pool,
    required int season,
    required int round,
  }) =>
      _service.roundStats(pool: pool, season: season, round: round);
}

/// Liest die serverseitig befüllte Tabelle player_match_stats (Quelle der
/// Wahrheit). Für noch nicht gespiegelte Spieltage (oder leere Antwort)
/// greift [_fallback] auf die Live-Berechnung zurück.
class DbStatsSource implements FantasyStatsSource {
  DbStatsSource(this._client, this._fallback);

  final SupabaseClient _client;
  final FantasyStatsSource _fallback;

  @override
  Future<Map<String, PlayerMatchStats>> roundStats({
    required List<FantasyPlayer> pool,
    required int season,
    required int round,
  }) async {
    final rows = await _client
        .from('player_match_stats')
        .select()
        .eq('season', season)
        .eq('round', round);

    if (rows.isEmpty) {
      return _fallback.roundStats(pool: pool, season: season, round: round);
    }

    final byId = {
      for (final r in rows) r['player_id'] as String: PlayerMatchStats.fromDb(r)
    };
    return {
      for (final p in pool)
        if (byId.containsKey(p.id)) p.id: byId[p.id]!
    };
  }
}
