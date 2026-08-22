import 'models.dart';

/// Ein Spiel im Spielplan eines favorisierten Teams — wettbewerbsübergreifend
/// (Bundesliga, DFB-Pokal …; europäische Wettbewerbe sind im Sportmonks-Trial
/// nicht enthalten). Trägt den Wettbewerbsnamen mit, da er je Spiel variiert.
class TeamFixture {
  const TeamFixture({
    required this.id,
    required this.kickoff,
    required this.status,
    required this.leagueName,
    required this.home,
    required this.away,
    this.leagueLogo,
    this.round = 0,
    this.homeScore,
    this.awayScore,
  });

  final String id;
  final DateTime kickoff;
  final FixtureStatus status;
  final String leagueName;

  /// Logo des Wettbewerbs (Sportmonks `image_path`), falls vorhanden.
  final String? leagueLogo;

  /// Spieltag (Liga) bzw. Runden-Ordinalzahl (Pokal); 0 = unbekannt.
  final int round;
  final TeamRef home;
  final TeamRef away;
  final int? homeScore;
  final int? awayScore;

  /// Wie bei [Fixture.hasScore]: erst ab Anpfiff. Vor dem Spiel liefert der
  /// Feed bereits ein 0:0, das sonst im Spielplan der Favoriten stünde.
  bool get hasScore =>
      status != FixtureStatus.scheduled &&
      homeScore != null &&
      awayScore != null;
}
