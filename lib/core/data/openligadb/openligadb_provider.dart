import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/match_detail.dart';
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

  @override
  Future<List<StandingRow>> getTable(LeagueInfo league, int season) async {
    final json =
        await _getJson('/getbltable/${league.providerLeagueKey}/$season');
    final raw = (json as List<dynamic>).cast<Map<String, dynamic>>().map((t) {
      final name = t['teamName'] as String? ?? '';
      final short = t['shortName'] as String?;
      final icon = (t['teamIconUrl'] as String?)
          ?.replaceFirst(RegExp('^http://'), 'https://');
      return (
        team: TeamRef(
          // teamInfoId == teamId der Spiele -> konsistent für Favoriten.
          id: 'openligadb:${t['teamInfoId']}',
          name: name,
          shortName: (short == null || short.isEmpty) ? name : short,
          iconUrl: (icon == null || icon.isEmpty) ? null : icon,
        ),
        points: t['points'] as int? ?? 0,
        played: t['matches'] as int? ?? 0,
        won: t['won'] as int? ?? 0,
        draw: t['draw'] as int? ?? 0,
        lost: t['lost'] as int? ?? 0,
        goalsFor: t['goals'] as int? ?? 0,
        goalsAgainst: t['opponentGoals'] as int? ?? 0,
      );
    }).toList();

    raw.sort((a, b) {
      final byPoints = b.points - a.points;
      if (byPoints != 0) return byPoints;
      final byDiff = (b.goalsFor - b.goalsAgainst) - (a.goalsFor - a.goalsAgainst);
      if (byDiff != 0) return byDiff;
      return b.goalsFor - a.goalsFor;
    });

    return [
      for (var i = 0; i < raw.length; i++)
        StandingRow(
          rank: i + 1,
          team: raw[i].team,
          points: raw[i].points,
          played: raw[i].played,
          won: raw[i].won,
          draw: raw[i].draw,
          lost: raw[i].lost,
          goalsFor: raw[i].goalsFor,
          goalsAgainst: raw[i].goalsAgainst,
        ),
    ];
  }

  /// Detaildaten eines einzelnen Spiels (Ergebnis, Halbzeit, Torschützen,
  /// Spielort) für die Spiel-Detailansicht.
  Future<MatchDetail> getMatchDetail(int matchId) async {
    final json = await _getJson('/getmatchdata/$matchId');
    return parseMatchDetail(json as Map<String, dynamic>);
  }

  /// Public für Tests. Parst die Detaildaten eines Spiels.
  static MatchDetail parseMatchDetail(Map<String, dynamic> m) {
    final kickoff = DateTime.parse(m['matchDateTimeUTC'] as String);
    final nowUtc = DateTime.now().toUtc();
    final results = (m['matchResults'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    (int, int)? byType(int type) {
      final r = results.where((e) => e['resultTypeID'] == type).firstOrNull;
      return r == null
          ? null
          : (r['pointsTeam1'] as int, r['pointsTeam2'] as int);
    }

    final regular = byType(2);
    final extra = byType(4);
    final endResult = regular != null;

    final flaggedFinished = m['matchIsFinished'] as bool? ?? false;
    final longOver = nowUtc.isAfter(kickoff.add(const Duration(hours: 3)));
    final isFinished = flaggedFinished || (endResult && longOver);
    final started = nowUtc.isAfter(kickoff);
    final status = isFinished
        ? FixtureStatus.finished
        : (started ? FixtureStatus.live : FixtureStatus.scheduled);

    // Tore in Spielreihenfolge; die treffende Seite ergibt sich daraus,
    // welcher Spielstand gestiegen ist (robust auch bei Eigentoren).
    final goalsRaw =
        (m['goals'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final goals = <MatchGoal>[];
    var prevH = 0, prevA = 0;
    for (final g in goalsRaw) {
      final h = g['scoreTeam1'] as int? ?? prevH;
      final a = g['scoreTeam2'] as int? ?? prevA;
      goals.add(MatchGoal(
        minute: g['matchMinute'] as int?,
        scorer: (g['goalGetterName'] as String?)?.trim().isNotEmpty == true
            ? g['goalGetterName'] as String
            : 'Tor',
        scoreHome: h,
        scoreAway: a,
        forHomeTeam: h > prevH,
        penalty: g['isPenalty'] as bool? ?? false,
        ownGoal: g['isOwnGoal'] as bool? ?? false,
      ));
      prevH = h;
      prevA = a;
    }

    // Maßgebliches Ergebnis: nach Verlängerung > regulär; live aus der
    // Torliste (sonst 0:0), vor Anstoß null.
    (int, int)? score;
    if (isFinished) {
      score = extra ?? regular ?? (goals.isNotEmpty
          ? (goals.last.scoreHome, goals.last.scoreAway)
          : null);
    } else if (status == FixtureStatus.live) {
      score = goals.isNotEmpty
          ? (goals.last.scoreHome, goals.last.scoreAway)
          : (0, 0);
    }

    final loc = m['location'] as Map<String, dynamic>?;

    return MatchDetail(
      id: 'openligadb:${m['matchID']}',
      home: _parseTeam(m['team1'] as Map<String, dynamic>),
      away: _parseTeam(m['team2'] as Map<String, dynamic>),
      kickoff: kickoff,
      status: status,
      homeScore: score?.$1,
      awayScore: score?.$2,
      halfTime: byType(1),
      afterExtraTime: extra,
      penalties: byType(5),
      goals: goals,
      stadium: loc?['locationStadium'] as String?,
      city: loc?['locationCity'] as String?,
    );
  }

  /// Robuster GET: OpenLigaDB (kostenlos) antwortet gelegentlich mit 5xx/429
  /// oder bricht die Verbindung ab. Statt sofort einen dauerhaften Fehler-State
  /// zu erzeugen (der gecachte FutureProvider zeigt dann bis zum manuellen
  /// Neuladen „konnte nicht geladen werden"), wird bis zu dreimal mit kurzer
  /// Backoff-Pause und Timeout wiederholt. Client-Fehler (4xx außer 429)
  /// werden sofort geworfen — ein Retry hilft dort nicht.
  Future<dynamic> _getJson(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    Object lastError = OpenLigaDbException('OpenLigaDB nicht erreichbar ($path)');
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
      try {
        final response =
            await _client.get(uri).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes));
        }
        final err = OpenLigaDbException(
            'OpenLigaDB-Anfrage fehlgeschlagen ($path): HTTP ${response.statusCode}');
        // 4xx (außer 429) sind dauerhaft -> sofort werfen, kein Retry.
        if (response.statusCode < 500 && response.statusCode != 429) throw err;
        lastError = err; // 5xx/429 -> erneut versuchen
      } on OpenLigaDbException {
        rethrow;
      } catch (e) {
        lastError = e; // Netzwerk/Timeout -> erneut versuchen
      }
    }
    throw lastError is OpenLigaDbException
        ? lastError
        : OpenLigaDbException('OpenLigaDB nicht erreichbar ($path): $lastError');
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
    final nowUtc = DateTime.now().toUtc();

    final endResult = (m['matchResults'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((r) => r['resultTypeID'] == 2)
        .firstOrNull;

    // OpenLigaDB pflegt das „Endergebnis" (resultTypeID 2) teils schon
    // WÄHREND des Spiels (v. a. WM-Feed). Als beendet werten wir daher nur:
    // explizit beendet ODER ein Endergebnis liegt vor UND der Anstoß ist so
    // lange her, dass das Spiel sicher vorbei ist (auch mit Verlängerung).
    // Sonst ist ein angepfiffenes Spiel LIVE — sonst stünde ein laufendes
    // Spiel fälschlich auf „beendet" (und zählte in der Tabelle nicht live).
    final flaggedFinished = m['matchIsFinished'] as bool? ?? false;
    final longOver = nowUtc.isAfter(kickoff.add(const Duration(hours: 3)));
    final isFinished = flaggedFinished || (endResult != null && longOver);

    final status = isFinished
        ? FixtureStatus.finished
        : (nowUtc.isAfter(kickoff)
            ? FixtureStatus.live
            : FixtureStatus.scheduled);

    (int, int)? score;
    if (isFinished) {
      score = _finalScore(m);
    } else if (status == FixtureStatus.live) {
      // Live-Stand: aus der Torliste; sonst aus dem (live gepflegten)
      // Endergebnis; sonst 0:0 (ein angepfiffenes Spiel steht mind. 0:0).
      score = _liveScore(m) ??
          (endResult != null
              ? (endResult['pointsTeam1'] as int,
                  endResult['pointsTeam2'] as int)
              : (0, 0));
    }
    // Geplante Spiele bleiben ohne Spielstand (null).

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

  /// Maßgebliches Ergebnis für die Wertung.
  ///
  /// K.-o.-Spiele werden **nach Verlängerung (120 Min)** gewertet; das
  /// Elfmeterschießen zählt nicht zum Ergebnis. Deshalb:
  /// `resultTypeID 4` (nach Verlängerung) hat Vorrang, sonst `resultTypeID 2`
  /// („Endergebnis"/reguläre Spielzeit). `resultTypeID 5` (Elfmeterschießen)
  /// wird nie verwendet — der OpenLigaDB-Feed schreibt es bei K.-o.-Spielen
  /// teils sogar fälschlich ins „Endergebnis" (Typ 2), daher der Vorrang von
  /// Typ 4 und die Filterung von Typ 5 im Fallback.
  static (int, int)? _finalScore(Map<String, dynamic> m) {
    final results = (m['matchResults'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final end = results.where((r) => r['resultTypeID'] == 4).firstOrNull ??
        results.where((r) => r['resultTypeID'] == 2).firstOrNull ??
        results.where((r) => r['resultTypeID'] != 5).lastOrNull;
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
