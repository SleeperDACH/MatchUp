import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/models.dart';
import '../sports_data_provider.dart';

/// Daten-Adapter für https://www.openligadb.de — kostenlose Ergebnis- und
/// Spielplandaten u. a. für Bundesliga (bl1) und 2. Bundesliga (bl2).
class OpenLigaDbProvider implements SportsDataProvider {
  OpenLigaDbProvider({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://api.openligadb.de';

  final http.Client _client;

  @override
  String get id => 'openligadb';

  @override
  Future<int> getCurrentRound(LeagueInfo league, int season) async {
    final json = await _getJson('/getcurrentgroup/${league.providerLeagueKey}');
    return (json as Map<String, dynamic>)['groupOrderID'] as int;
  }

  @override
  Future<List<RoundInfo>> getRounds(LeagueInfo league, int season) async {
    final json = await _getJson(
        '/getavailablegroups/${league.providerLeagueKey}/$season');
    return (json as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((g) => RoundInfo(
              number: g['groupOrderID'] as int,
              name: g['groupName'] as String? ?? '',
            ))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  @override
  Future<List<Fixture>> getRoundFixtures(
      LeagueInfo league, int season, int round) async {
    final json = await _getJson(
        '/getmatchdata/${league.providerLeagueKey}/$season/$round');
    return _parseMatches(json as List<dynamic>, league, season);
  }

  @override
  Future<List<Fixture>> getSeasonFixtures(LeagueInfo league, int season) async {
    final json =
        await _getJson('/getmatchdata/${league.providerLeagueKey}/$season');
    return _parseMatches(json as List<dynamic>, league, season);
  }

  Future<dynamic> _getJson(String path) async {
    final response = await _client.get(Uri.parse('$_baseUrl$path'));
    if (response.statusCode != 200) {
      throw OpenLigaDbException(
          'OpenLigaDB-Anfrage fehlgeschlagen ($path): HTTP ${response.statusCode}');
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  List<Fixture> _parseMatches(
      List<dynamic> matches, LeagueInfo league, int season) {
    return matches
        .map((m) => parseMatch(m as Map<String, dynamic>, league, season))
        .toList()
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  }

  /// Public für Tests.
  static Fixture parseMatch(
      Map<String, dynamic> m, LeagueInfo league, int season) {
    final kickoff = DateTime.parse(m['matchDateTimeUTC'] as String);
    final isFinished = m['matchIsFinished'] as bool? ?? false;

    (int, int)? score;
    if (isFinished) {
      score = _finalScore(m);
    } else {
      score = _liveScore(m);
    }

    final status = isFinished
        ? FixtureStatus.finished
        : (DateTime.now().toUtc().isAfter(kickoff)
            ? FixtureStatus.live
            : FixtureStatus.scheduled);

    final group = m['group'] as Map<String, dynamic>? ?? const {};

    return Fixture(
      id: 'openligadb:${m['matchID']}',
      leagueId: league.id,
      season: season,
      round: group['groupOrderID'] as int? ?? 0,
      roundName: group['groupName'] as String? ?? '',
      kickoff: kickoff,
      home: _parseTeam(m['team1'] as Map<String, dynamic>),
      away: _parseTeam(m['team2'] as Map<String, dynamic>),
      status: status,
      homeScore: score?.$1,
      awayScore: score?.$2,
    );
  }

  static TeamRef _parseTeam(Map<String, dynamic> t) {
    final name = t['teamName'] as String? ?? '';
    final short = t['shortName'] as String?;
    // Manche Icon-URLs sind http:// — iOS blockt das (ATS), die Hosts
    // können aber alle https.
    final icon = (t['teamIconUrl'] as String?)
        ?.replaceFirst(RegExp('^http://'), 'https://');
    return TeamRef(
      id: 'openligadb:${t['teamId']}',
      name: name,
      shortName: (short == null || short.isEmpty) ? name : short,
      iconUrl: (icon == null || icon.isEmpty) ? null : icon,
    );
  }

  /// Endergebnis: resultTypeID 2.
  static (int, int)? _finalScore(Map<String, dynamic> m) {
    final results = (m['matchResults'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final end = results.where((r) => r['resultTypeID'] == 2).firstOrNull ??
        results.lastOrNull;
    if (end == null) return null;
    return (end['pointsTeam1'] as int, end['pointsTeam2'] as int);
  }

  /// Während des Spiels gibt es noch kein Endergebnis; der Spielstand
  /// ergibt sich aus dem letzten Eintrag der Torliste.
  static (int, int)? _liveScore(Map<String, dynamic> m) {
    final goals =
        (m['goals'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    if (goals.isEmpty) return null;
    final last = goals.last;
    return (last['scoreTeam1'] as int? ?? 0, last['scoreTeam2'] as int? ?? 0);
  }
}

class OpenLigaDbException implements Exception {
  OpenLigaDbException(this.message);
  final String message;

  @override
  String toString() => message;
}
