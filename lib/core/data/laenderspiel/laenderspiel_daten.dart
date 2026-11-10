import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/match_detail.dart';
import '../../models/models.dart';

/// **Aufstellung, Wechsel und Karten für Länderspiele** (09.11.2026).
///
/// Spielplan und Stand kommen kostenlos von OpenLigaDB (`DFBN`), die aber nur
/// Tore kennt. Den Rest holt die Edge Function `laenderspiel` von
/// API-Football und merkt ihn sich; ihre Antwort trägt dieselben Feldnamen
/// wie die `sportmonks`-Function. Gilt nur für Spiele der Nationalmannschaft —
/// woran das zu erkennen ist, sagt [istLaenderspiel].
bool istLaenderspiel(MatchDetail d) =>
    d.id.startsWith('openligadb:') &&
    (d.home.name == 'Deutschland' || d.away.name == 'Deutschland');

/// Holt die Ergänzung und legt sie über [basis]. Scheitert der Abruf, bleibt
/// es bei [basis] — Tore und Stand stehen dann trotzdem da.
Future<MatchDetail> mitLaenderspielDaten(
  MatchDetail basis,
  SupabaseClient client,
) async {
  try {
    final res = await client.functions.invoke(
      'laenderspiel',
      body: {'anstoss': basis.kickoff.toUtc().toIso8601String()},
    );
    final data = res.data;
    if (data is! Map || data['detail'] is! Map) return basis;
    return ergaenzeLaenderspiel(
      basis,
      (data['detail'] as Map).cast<String, dynamic>(),
    );
  } catch (_) {
    return basis;
  }
}

/// Pur, für Tests: legt Aufstellung, Ereignisse, Statistik und Formation aus
/// [j] über [basis]. **Stand und Zustand bleiben von OpenLigaDB** — dieselbe
/// Quelle wie die Zeile im Live-Tab, sonst stünden dort und im Detail
/// verschiedene Ergebnisse. Fehlt bei OpenLigaDB ein Stand, nimmt es den
/// von API-Football.
MatchDetail ergaenzeLaenderspiel(MatchDetail basis, Map<String, dynamic> j) {
  List<Map<String, dynamic>> liste(String k) =>
      (j[k] as List? ?? const []).cast<Map<String, dynamic>>();
  int? n(Object? v) => (v as num?)?.toInt();

  final lineups = [
    for (final l in liste('lineups'))
      () {
        final feld = (l['field'] as String?)?.split(':');
        return LineupPlayer(
          name: (l['name'] as String?) ?? '?',
          forHomeTeam: l['for_home'] == true,
          starting: l['starting'] == true,
          playerId: n(l['player_id']),
          number: n(l['number']),
          position: n(l['position']),
          row: feld != null && feld.isNotEmpty ? int.tryParse(feld[0]) : null,
          col: feld != null && feld.length > 1 ? int.tryParse(feld[1]) : null,
        );
      }(),
  ];
  final events = [
    for (final e in liste('events'))
      MatchEvent(
        minute: n(e['minute']) ?? 0,
        extra: n(e['extra']),
        type: (e['type'] as String?) ?? '',
        forHomeTeam: e['for_home'] == true,
        player: e['player'] as String?,
        playerId: n(e['player_id']),
        related: e['related'] as String?,
        relatedPlayerId: n(e['related_player_id']),
        result: e['result'] as String?,
      ),
  ];
  final stats = [
    for (final s in liste('stats'))
      MatchStat(
        label: (s['label'] as String?) ?? '',
        home: (s['home'] as num?) ?? 0,
        away: (s['away'] as num?) ?? 0,
      ),
  ];
  final ohneStand = basis.homeScore == null || basis.awayScore == null;
  return MatchDetail(
    id: basis.id,
    home: basis.home,
    away: basis.away,
    kickoff: basis.kickoff,
    status: basis.status,
    homeScore: ohneStand ? n(j['home_score']) : basis.homeScore,
    awayScore: ohneStand ? n(j['away_score']) : basis.awayScore,
    goals: basis.goals,
    halfTime: basis.halfTime,
    afterExtraTime: basis.afterExtraTime,
    penalties: basis.penalties,
    minute: basis.status == FixtureStatus.live ? n(j['minute']) : null,
    phase: basis.phase,
    stadium: basis.stadium,
    city: basis.city,
    leagueKey: basis.leagueKey,
    homeFormation: (j['home_formation'] as String?) ?? basis.homeFormation,
    awayFormation: (j['away_formation'] as String?) ?? basis.awayFormation,
    lineups: lineups.isEmpty ? basis.lineups : lineups,
    stats: stats.isEmpty ? basis.stats : stats,
    // Die Ereignisse der Quelle kennen auch Karten und Wechsel; die aus den
    // OpenLigaDB-Toren gebauten bleiben nur, solange sie nichts liefert.
    events: events.isEmpty ? basis.events : events,
  );
}
