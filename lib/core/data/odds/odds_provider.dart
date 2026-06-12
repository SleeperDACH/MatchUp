import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import 'match_odds.dart';

/// Adapter-Interface für eine Wettquoten-Quelle. Analog zu
/// `SportsDataProvider`, aber bewusst getrennt: Quoten kommen aus einer
/// anderen Quelle als die Spielpläne.
abstract class OddsProvider {
  /// Aktuelle 1X2-Quoten für einen Wettbewerb (Sport-Key der Quelle).
  Future<List<MatchOdds>> fetchOdds(String sportKey);
}

/// Quoten über die Supabase Edge Function `odds`: Der geheime API-Key bleibt
/// serverseitig, die Function cached und liefert dieselbe JSON-Struktur wie
/// the-odds-api. Standardweg, sobald Supabase konfiguriert ist.
class SupabaseOddsProvider implements OddsProvider {
  @override
  Future<List<MatchOdds>> fetchOdds(String sportKey) async {
    final res = await Supabase.instance.client.functions.invoke(
      'odds',
      body: {'sport': sportKey},
    );
    final data = res.data;
    if (data is List) return parseOddsEvents(data);
    return const [];
  }
}

/// Quoten direkt von https://the-odds-api.com — nur für lokale Entwicklung
/// ohne Backend (Key per `--dart-define=ODDS_API_KEY`). Im Web-/Prod-Betrieb
/// läuft alles über [SupabaseOddsProvider], damit kein Key im Bundle landet.
class TheOddsApiProvider implements OddsProvider {
  TheOddsApiProvider({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.the-odds-api.com/v4';

  final http.Client _client;

  @override
  Future<List<MatchOdds>> fetchOdds(String sportKey) async {
    if (!AppConfig.hasOdds) return const [];
    final uri = Uri.parse('$_baseUrl/sports/$sportKey/odds/').replace(
      queryParameters: {
        'apiKey': AppConfig.oddsApiKey,
        'regions': 'eu',
        'markets': 'h2h',
        'oddsFormat': 'decimal',
      },
    );
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Quoten-Abruf fehlgeschlagen (${res.statusCode}).');
    }
    return parseOddsEvents(jsonDecode(res.body) as List<dynamic>);
  }
}

/// Wandelt die Event-Liste der Quoten-API in [MatchOdds] um. Geteilt von
/// beiden Providern (direkt vs. über die Edge Function).
List<MatchOdds> parseOddsEvents(List<dynamic> data) => data
    .map((e) => _parseEvent(e as Map<String, dynamic>))
    .whereType<MatchOdds>()
    .toList();

/// Ein Event → [MatchOdds]. Nimmt den ersten Buchmacher mit vollständigem
/// 1X2-Markt; `null`, wenn keiner taugt.
MatchOdds? _parseEvent(Map<String, dynamic> event) {
  final home = event['home_team'] as String?;
  final away = event['away_team'] as String?;
  final commence = event['commence_time'] as String?;
  if (home == null || away == null || commence == null) return null;

  final bookmakers = (event['bookmakers'] as List<dynamic>? ?? []);
  for (final b in bookmakers) {
    final bm = b as Map<String, dynamic>;
    final markets = (bm['markets'] as List<dynamic>? ?? []);
    for (final m in markets) {
      final market = m as Map<String, dynamic>;
      if (market['key'] != 'h2h') continue;
      final outcomes = (market['outcomes'] as List<dynamic>? ?? []);
      double? h, d, a;
      for (final o in outcomes) {
        final out = o as Map<String, dynamic>;
        final name = out['name'] as String?;
        final price = (out['price'] as num?)?.toDouble();
        if (name == null || price == null) continue;
        if (name == home) {
          h = price;
        } else if (name == away) {
          a = price;
        } else if (name.toLowerCase() == 'draw') {
          d = price;
        }
      }
      if (h != null && d != null && a != null) {
        return MatchOdds(
          homeTeam: home,
          awayTeam: away,
          commenceTime: DateTime.parse(commence),
          homeWin: h,
          draw: d,
          awayWin: a,
          bookmaker: bm['title'] as String? ?? 'Buchmacher',
        );
      }
    }
  }
  return null;
}
