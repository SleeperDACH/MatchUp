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

  /// Alle gespielten Spieltage einer Saison auf einmal (Spieltag →
  /// Spieler-ID → Stats). Für die Head-to-Head-Bilanz über die Saison.
  /// Leer, wenn keine serverseitigen Stats vorliegen (lokaler Modus).
  Future<Map<int, Map<String, PlayerMatchStats>>> seasonStats({
    required int season,
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

  // Saison-weite Stats wären live zu teuer (ein Abruf je Spieltag) — die
  // H2H-Bilanz setzt serverseitige Stats voraus.
  @override
  Future<Map<int, Map<String, PlayerMatchStats>>> seasonStats({
    required int season,
  }) async =>
      const {};
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

  @override
  Future<Map<int, Map<String, PlayerMatchStats>>> seasonStats({
    required int season,
  }) async {
    // **Seitenweise, nicht in einem Rutsch.** PostgREST gibt je Abfrage
    // höchstens `max_rows` Zeilen heraus (1000), und das **stillschweigend**:
    // keine Fehlermeldung, nur eine kürzere Liste. Eine Saison hat rund 285
    // Zeilen je Spieltag; ab dem vierten fehlten deshalb zufällig verteilte
    // Spieler ganzer Runden — gemessen am 11.10.2026: 1000 von 1354 Zeilen,
    // von Spieltag 5 nur 81 von 219. Betroffen war alles, was die Saison
    // liest: Spielerprofil, Tabelle, Bilanz, Playoffs, Free Agency, Trades.
    //
    // Die Sortierung ist Pflicht: Ohne sie ist die Reihenfolge zwischen zwei
    // Seiten nicht festgelegt, und eine Zeile könnte doppelt oder gar nicht
    // kommen.
    const seite = 1000;
    final rows = <Map<String, dynamic>>[];
    for (var ab = 0;; ab += seite) {
      final teil = await _client
          .from('player_match_stats')
          .select()
          .eq('season', season)
          .order('round')
          .order('player_id')
          .range(ab, ab + seite - 1);
      rows.addAll(teil);
      if (teil.length < seite) break;
    }
    final out = <int, Map<String, PlayerMatchStats>>{};
    for (final r in rows) {
      final round = r['round'] as int;
      (out[round] ??= {})[r['player_id'] as String] =
          PlayerMatchStats.fromDb(r);
    }
    return out;
  }
}
