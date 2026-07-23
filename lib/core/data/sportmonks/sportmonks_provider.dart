import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/match_detail.dart';
import '../../models/models.dart';
import '../../models/team_fixture.dart';
import '../../models/top_scorer.dart';
import '../sports_data_provider.dart';

/// Daten-Adapter für die **Sportmonks Football API** — über die Edge Function
/// `sportmonks` (Key bleibt serverseitig). Deckt die fünf deutschen Ligen des
/// Plans ab (Bundesliga 82, 2. Bundesliga 85, 3. Liga 88, DFB-Pokal 109,
/// Frauen-Bundesliga 1740; `LeagueInfo.providerLeagueKey` = Sportmonks-ID).
///
/// Fixture-/Team-IDs sind provider-qualifiziert (`sportmonks:<id>`). Runden
/// werden aus den Saison-Fixtures abgeleitet (ein Function-Call, serverseitig
/// gecacht), statt eigene Endpunkte zu bemühen.
class SupabaseSportmonksProvider implements SportsDataProvider {
  SupabaseSportmonksProvider();

  SupabaseClient get _client => Supabase.instance.client;

  @override
  String get id => 'sportmonks';

  Future<Map<String, dynamic>> _call(String kind,
      {String? leagueKey, String? fixtureId, String? teamId}) async {
    final res = await _client.functions.invoke('sportmonks', body: {
      'kind': kind,
      'leagueKey': ?leagueKey,
      'fixtureId': ?fixtureId,
      'teamId': ?teamId,
    });
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw SportmonksException(data['error'].toString());
    }
    if (data is! Map<String, dynamic>) {
      throw SportmonksException('Unerwartete Antwort der Sportmonks-Function.');
    }
    return data;
  }

  @override
  Future<List<Fixture>> getSeasonFixtures(LeagueInfo league, int season) async {
    final data = await _call('seasonFixtures', leagueKey: league.sportmonksKey!);
    final list = (data['fixtures'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return [for (final f in list) fixtureFromJson(f, league, season)]
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  }

  @override
  Future<List<Fixture>> getRoundFixtures(
      LeagueInfo league, int season, int round) async {
    final all = await getSeasonFixtures(league, season);
    return [for (final f in all) if (f.round == round) f];
  }

  @override
  Future<List<RoundInfo>> getRounds(LeagueInfo league, int season) async {
    final all = await getSeasonFixtures(league, season);
    final byNumber = <int, String>{};
    for (final f in all) {
      byNumber[f.round] = f.roundName;
    }
    final rounds = [
      for (final e in byNumber.entries) RoundInfo(number: e.key, name: e.value)
    ]..sort((a, b) => a.number.compareTo(b.number));
    return rounds;
  }

  @override
  Future<int> getCurrentRound(LeagueInfo league, int season) async {
    final all = await getSeasonFixtures(league, season);
    if (all.isEmpty) return 1;
    // Erste noch nicht beendete Runde; sonst die letzte.
    final pending = all.where((f) => f.status != FixtureStatus.finished);
    if (pending.isNotEmpty) {
      return pending
          .reduce((a, b) => a.kickoff.isBefore(b.kickoff) ? a : b)
          .round;
    }
    return all.map((f) => f.round).reduce((a, b) => a > b ? a : b);
  }

  @override
  Future<List<StandingRow>> getTable(LeagueInfo league, int season) async {
    final data = await _call('standings', leagueKey: league.sportmonksKey!);
    final rows = (data['standings'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .where((r) => r['team'] != null)
        .map((r) => (
              position: (r['position'] as num?)?.toInt() ?? 0,
              row: standingFromJson(r),
            ))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return [for (final r in rows) r.row];
  }

  /// Spieldetail (Ergebnis, Torschützen, Ort) für die Detailansicht.
  Future<MatchDetail> getMatchDetail(String fixtureId) async {
    final raw = fixtureId.split(':').last;
    final data = await _call('fixture', fixtureId: raw);
    return matchDetailFromJson(data);
  }

  /// Spielplan eines Teams (wettbewerbsübergreifend, dt. Wettbewerbe) —
  /// [teamId] ist die reine Sportmonks-Team-ID (ohne `sportmonks:`-Präfix).
  Future<List<TeamFixture>> getTeamFixtures(String teamId) async {
    final data = await _call('teamFixtures', teamId: teamId);
    final list =
        (data['fixtures'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [for (final f in list) _teamFixtureFromJson(f)]
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
  }

  static TeamFixture _teamFixtureFromJson(Map<String, dynamic> j) {
    final home = j['home'] as Map<String, dynamic>?;
    final away = j['away'] as Map<String, dynamic>?;
    const placeholder = {'id': 0, 'name': 'TBD', 'short': 'TBD', 'img': null};
    return TeamFixture(
      id: 'sportmonks:${j['id']}',
      kickoff: DateTime.parse(j['starting_at'] as String).toUtc(),
      status: statusFrom(j['state'] as String? ?? 'NS'),
      leagueName: (j['league_name'] as String?) ?? '',
      leagueLogo: j['league_image'] as String?,
      round: (j['round'] as num?)?.toInt() ?? 0,
      home: _team(home ?? placeholder),
      away: _team(away ?? placeholder),
      homeScore: (j['home_score'] as num?)?.toInt(),
      awayScore: (j['away_score'] as num?)?.toInt(),
    );
  }

  /// Torjägerliste (Tore) der Liga — aktuelle Saison, sonst letzte mit Daten.
  Future<TopScorersResult> getTopScorers(LeagueInfo league) async {
    final data = await _call('topscorers', leagueKey: league.sportmonksKey!);
    final list =
        (data['scorers'] as List? ?? const []).cast<Map<String, dynamic>>();
    return TopScorersResult(
      current: data['current'] == true,
      seasonName: data['season_name'] as String?,
      scorers: [for (final s in list) TopScorer.fromJson(s)],
    );
  }

  // --- Mapping (normalisierte Function-Antwort → App-Modelle) --------------

  static FixtureStatus statusFrom(String state) {
    final s = state.toUpperCase();
    if (s == 'FT' ||
        s == 'AET' ||
        s == 'FT_PEN' ||
        s == 'AWARDED' ||
        s == 'WALKOVER') {
      return FixtureStatus.finished;
    }
    if (s.startsWith('INPLAY') ||
        s == 'HT' ||
        s == 'BREAK' ||
        s == 'ET' ||
        s == 'EXTRA_TIME' ||
        s.contains('PEN') && s != 'FT_PEN' ||
        s == 'PENALTIES') {
      return FixtureStatus.live;
    }
    return FixtureStatus.scheduled;
  }

  static TeamRef _team(Map<String, dynamic> t) => TeamRef(
        id: 'sportmonks:${t['id']}',
        name: (t['name'] as String?) ?? '',
        shortName: (t['short'] as String?)?.isNotEmpty == true
            ? t['short'] as String
            : (t['name'] as String?) ?? '',
        iconUrl: t['img'] as String?,
      );

  static Fixture fixtureFromJson(
      Map<String, dynamic> j, LeagueInfo league, int season) {
    final status = statusFrom(j['state'] as String? ?? 'NS');
    final home = j['home'] as Map<String, dynamic>?;
    final away = j['away'] as Map<String, dynamic>?;
    final placeholder = {
      'id': 0,
      'name': 'TBD',
      'short': 'TBD',
      'img': null,
    };
    return Fixture(
      id: 'sportmonks:${j['id']}',
      leagueId: league.id,
      season: season,
      round: (j['round'] as num?)?.toInt() ?? 0,
      roundName: (j['round_name'] as String?) ?? '',
      kickoff: DateTime.parse(j['starting_at'] as String).toUtc(),
      home: _team(home ?? placeholder),
      away: _team(away ?? placeholder),
      status: status,
      homeScore: (j['home_score'] as num?)?.toInt(),
      awayScore: (j['away_score'] as num?)?.toInt(),
    );
  }

  static StandingRow standingFromJson(Map<String, dynamic> r) {
    final t = r['team'] as Map<String, dynamic>;
    int n(String k) => (r[k] as num?)?.toInt() ?? 0;
    return StandingRow(
      rank: (r['position'] as num?)?.toInt() ?? 0,
      team: _team(t),
      points: n('points'),
      played: n('played'),
      won: n('won'),
      draw: n('draw'),
      lost: n('lost'),
      goalsFor: n('goals_for'),
      goalsAgainst: n('goals_against'),
    );
  }

  static MatchDetail matchDetailFromJson(Map<String, dynamic> j) {
    final status = statusFrom(j['state'] as String? ?? 'NS');
    final venue = j['venue'] as Map<String, dynamic>?;
    final goalsRaw =
        (j['goals'] as List? ?? const []).cast<Map<String, dynamic>>();
    var prevH = 0, prevA = 0;
    final goals = <MatchGoal>[];
    for (final g in goalsRaw) {
      final h = (g['score_home'] as num?)?.toInt() ??
          (g['for_home'] == true ? prevH + 1 : prevH);
      final a = (g['score_away'] as num?)?.toInt() ??
          (g['for_home'] == true ? prevA : prevA + 1);
      goals.add(MatchGoal(
        minute: (g['minute'] as num?)?.toInt(),
        scorer: (g['scorer'] as String?)?.trim().isNotEmpty == true
            ? g['scorer'] as String
            : 'Tor',
        scoreHome: h,
        scoreAway: a,
        forHomeTeam: g['for_home'] == true,
        penalty: g['penalty'] == true,
        ownGoal: g['own_goal'] == true,
      ));
      prevH = h;
      prevA = a;
    }
    final home = j['home'] as Map<String, dynamic>?;
    final away = j['away'] as Map<String, dynamic>?;
    final lineups = [
      for (final l in (j['lineups'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        () {
          final field = (l['field'] as String?)?.split(':');
          return LineupPlayer(
            name: (l['name'] as String?) ?? '?',
            forHomeTeam: l['for_home'] == true,
            starting: l['starting'] == true,
            playerId: (l['player_id'] as num?)?.toInt(),
            number: (l['number'] as num?)?.toInt(),
            position: (l['position'] as num?)?.toInt(),
            row: field != null && field.isNotEmpty
                ? int.tryParse(field[0])
                : null,
            col: field != null && field.length > 1
                ? int.tryParse(field[1])
                : null,
          );
        }()
    ];
    final stats = [
      for (final s in (j['stats'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        MatchStat(
          label: (s['label'] as String?) ?? '',
          home: (s['home'] as num?) ?? 0,
          away: (s['away'] as num?) ?? 0,
        )
    ];
    final events = [
      for (final e in (j['events'] as List? ?? const [])
          .cast<Map<String, dynamic>>())
        MatchEvent(
          minute: (e['minute'] as num?)?.toInt() ?? 0,
          extra: (e['extra'] as num?)?.toInt(),
          type: (e['type'] as String?) ?? '',
          forHomeTeam: e['for_home'] == true,
          player: e['player'] as String?,
          playerId: (e['player_id'] as num?)?.toInt(),
          related: e['related'] as String?,
          result: e['result'] as String?,
        )
    ];
    return MatchDetail(
      id: 'sportmonks:${j['id']}',
      home: _team(home ?? const {'id': 0, 'name': '?', 'short': '?'}),
      away: _team(away ?? const {'id': 0, 'name': '?', 'short': '?'}),
      kickoff: DateTime.parse(j['starting_at'] as String).toUtc(),
      status: status,
      homeScore: (j['home_score'] as num?)?.toInt(),
      awayScore: (j['away_score'] as num?)?.toInt(),
      goals: goals,
      stadium: venue?['name'] as String?,
      city: venue?['city'] as String?,
      leagueKey: j['league_key'] as String?,
      homeFormation: j['home_formation'] as String?,
      awayFormation: j['away_formation'] as String?,
      lineups: lineups,
      stats: stats,
      events: events,
    );
  }
}

class SportmonksException implements Exception {
  SportmonksException(this.message);
  final String message;
  @override
  String toString() => message;
}
