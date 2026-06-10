import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';

/// Leitet echte Spieler-Leistungsdaten aus den kostenlosen OpenLigaDB-
/// Spieltagsdaten ab: Tore (per Torschützen-Nachname) und Zu-Null
/// (per Verein des Spielers). Assists/Karten/Minuten liefert der freie
/// Feed nicht — diese bleiben 0, bis ein vollständiger Stats-Feed
/// angebunden wird.
///
/// Bewusste Näherungen (klar kommuniziert): Tore werden über den
/// Nachnamen zugeordnet; Zu-Null wird Torwart/Abwehr eines Vereins
/// gutgeschrieben, dessen Spiel ohne Gegentor endete (ohne Aufstellung
/// lässt sich der tatsächliche Einsatz nicht prüfen).
class RoundScoringService {
  RoundScoringService({http.Client? client, this.leagueKey = 'bl1'})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String leagueKey;

  static const _baseUrl = 'https://api.openligadb.de';

  Future<Map<String, PlayerMatchStats>> roundStats({
    required List<FantasyPlayer> pool,
    required int season,
    required int round,
  }) async {
    final res = await _client
        .get(Uri.parse('$_baseUrl/getmatchdata/$leagueKey/$season/$round'));
    if (res.statusCode != 200) {
      throw Exception('OpenLigaDB HTTP ${res.statusCode}');
    }
    final matches =
        (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
    return computeStats(pool: pool, matches: matches);
  }

  /// Reine Berechnung (für Tests) aus rohen OpenLigaDB-Matchdaten.
  static Map<String, PlayerMatchStats> computeStats({
    required List<FantasyPlayer> pool,
    required List<Map<String, dynamic>> matches,
  }) {
    final goalsByLastName = <String, int>{};
    final cleanSheetClubs = <String>{}; // normalisierte Vereins-Cores

    for (final m in matches) {
      if (m['matchIsFinished'] != true) continue;
      final t1 = (m['team1']?['teamName'] as String?) ?? '';
      final t2 = (m['team2']?['teamName'] as String?) ?? '';
      final results = (m['matchResults'] as List?)?.cast<Map<String, dynamic>>();
      final end = results
          ?.where((r) => r['resultTypeID'] == 2)
          .firstOrNull;
      if (end != null) {
        final s1 = end['pointsTeam1'] as int? ?? 0;
        final s2 = end['pointsTeam2'] as int? ?? 0;
        if (s2 == 0) cleanSheetClubs.add(_core(t1));
        if (s1 == 0) cleanSheetClubs.add(_core(t2));
      }
      for (final g in (m['goals'] as List? ?? const [])
          .cast<Map<String, dynamic>>()) {
        final name = g['goalGetterName'] as String?;
        final own = g['isOwnGoal'] as bool? ?? false;
        if (name == null || name.isEmpty || own) continue;
        final ln = _lastName(name);
        if (ln.isEmpty) continue;
        goalsByLastName[ln] = (goalsByLastName[ln] ?? 0) + 1;
      }
    }

    final result = <String, PlayerMatchStats>{};
    for (final p in pool) {
      final goals = goalsByLastName[_lastName(p.name)] ?? 0;
      final cs = (p.position == PlayerPosition.gk ||
              p.position == PlayerPosition.def) &&
          cleanSheetClubs.contains(_core(p.club));
      if (goals == 0 && !cs) continue; // keine Daten -> kein Eintrag
      result[p.id] = PlayerMatchStats(
        goals: goals,
        played: goals > 0, // bestätigter Einsatz nur bei Torschütze
        cleanSheet: cs,
      );
    }
    return result;
  }

  static String _lastName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last.toLowerCase();
  }

  /// Markantestes Wort eines Vereinsnamens (längstes Token) zum groben
  /// Abgleich (z. B. „bayern", „leverkusen").
  static String _core(String club) {
    final tokens = club
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zäöüß ]'), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 3)
        .toList();
    if (tokens.isEmpty) return club.toLowerCase();
    tokens.sort((a, b) => b.length.compareTo(a.length));
    return tokens.first;
  }
}
