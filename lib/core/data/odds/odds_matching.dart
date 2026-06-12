import '../../models/models.dart';
import 'match_odds.dart';
import 'odds_team_resolver.dart';

/// Ordnet Quoten den Fixtures zu — Schlüssel ist die Fixture-ID. Das
/// Matching läuft über die OpenLigaDB-Kürzel (per [OddsTeamResolver]) plus
/// einen Zeitfenster-Check, damit ein K.o.-Rückspiel nicht die
/// Gruppenphasen-Quote erbt. Heim/Auswärts werden bei Bedarf gedreht.
Map<String, MatchOdds> matchOdds(
  String sportKey,
  List<Fixture> fixtures,
  List<MatchOdds> odds,
) {
  // Quoten nach Code-Paar indizieren (beide Orientierungen).
  final result = <String, MatchOdds>{};
  for (final fixture in fixtures) {
    final homeCode = fixture.home.shortName;
    final awayCode = fixture.away.shortName;
    for (final o in odds) {
      final oHome = OddsTeamResolver.codeFor(sportKey, o.homeTeam);
      final oAway = OddsTeamResolver.codeFor(sportKey, o.awayTeam);
      if (oHome == null || oAway == null) continue;
      if (!_closeInTime(fixture.kickoff, o.commenceTime)) continue;
      if (oHome == homeCode && oAway == awayCode) {
        result[fixture.id] = o;
        break;
      }
      if (oHome == awayCode && oAway == homeCode) {
        result[fixture.id] = o.swapped;
        break;
      }
    }
  }
  return result;
}

/// Quelle und OpenLigaDB können den Anstoß minimal unterschiedlich führen
/// (Zeitzone, Rundung) — 2 Tage Toleranz trennt sicher Hin-/Rückspiele.
bool _closeInTime(DateTime a, DateTime b) =>
    a.toUtc().difference(b.toUtc()).abs() < const Duration(days: 2);
