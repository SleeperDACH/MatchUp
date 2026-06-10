import '../models/fantasy_models.dart';
import 'fantasy_data_provider.dart';

/// Vorläufiger, von Hand kuratierter Bundesliga-Spielerpool.
///
/// Bewusst als Seed gekennzeichnet: Die Geburtsdaten sind auf das
/// Geburtsjahr genau (für die U20-Logik ausreichend), die Liste ist
/// nicht vollständig. Ein echter Daten-Feed ersetzt diesen Pool später
/// hinter demselben [FantasyDataProvider]-Interface. Bis dahin reicht er,
/// um Liga-Erstellung, Snake-Draft und Dynasty-U20-Mechanik zu betreiben.
class SeedFantasyDataProvider implements FantasyDataProvider {
  const SeedFantasyDataProvider();

  @override
  String get id => 'seed-bundesliga';

  @override
  Future<List<FantasyPlayer>> getPlayerPool({required int season}) async =>
      _players;

  @override
  Future<int?> getPlayerPoints({
    required String playerId,
    required int season,
    required int round,
  }) async =>
      // Noch keine Live-Stats angebunden.
      null;
}

FantasyPlayer _p(
  String id,
  String name,
  PlayerPosition pos,
  String club,
  int birthYear,
  String nat, {
  bool foreignNewcomer = false,
}) =>
    FantasyPlayer(
      id: 'seed:$id',
      name: name,
      position: pos,
      club: club,
      birthDate: DateTime(birthYear, 1, 1),
      nationality: nat,
      isForeignNewcomer: foreignNewcomer,
    );

const _gk = PlayerPosition.gk;
const _def = PlayerPosition.def;
const _mid = PlayerPosition.mid;
const _fwd = PlayerPosition.fwd;

final List<FantasyPlayer> _players = [
  // FC Bayern München
  _p('1', 'Manuel Neuer', _gk, 'FC Bayern München', 1986, 'de'),
  _p('2', 'Joshua Kimmich', _mid, 'FC Bayern München', 1995, 'de'),
  _p('3', 'Alphonso Davies', _def, 'FC Bayern München', 2000, 'ca'),
  _p('4', 'Harry Kane', _fwd, 'FC Bayern München', 1993, 'gb-eng'),
  _p('5', 'Jamal Musiala', _mid, 'FC Bayern München', 2003, 'de'),
  _p('6', 'Aleksandar Pavlović', _mid, 'FC Bayern München', 2004, 'de'),
  // Bayer 04 Leverkusen
  _p('7', 'Granit Xhaka', _mid, 'Bayer 04 Leverkusen', 1992, 'ch'),
  _p('8', 'Florian Wirtz', _mid, 'Bayer 04 Leverkusen', 2003, 'de'),
  _p('9', 'Jeremie Frimpong', _def, 'Bayer 04 Leverkusen', 2000, 'nl'),
  _p('10', 'Victor Boniface', _fwd, 'Bayer 04 Leverkusen', 2000, 'ng'),
  // Borussia Dortmund
  _p('11', 'Gregor Kobel', _gk, 'Borussia Dortmund', 1997, 'ch'),
  _p('12', 'Nico Schlotterbeck', _def, 'Borussia Dortmund', 1999, 'de'),
  _p('13', 'Julian Brandt', _mid, 'Borussia Dortmund', 1996, 'de'),
  _p('14', 'Karim Adeyemi', _fwd, 'Borussia Dortmund', 2002, 'de'),
  // VfB Stuttgart
  _p('15', 'Angelo Stiller', _mid, 'VfB Stuttgart', 2001, 'de'),
  _p('16', 'Deniz Undav', _fwd, 'VfB Stuttgart', 1996, 'de'),
  // RB Leipzig
  _p('17', 'Benjamin Šeško', _fwd, 'RB Leipzig', 2003, 'si'),
  _p('18', 'Xavi Simons', _mid, 'RB Leipzig', 2003, 'nl', foreignNewcomer: true),
  // Eintracht Frankfurt
  _p('19', 'Hugo Ekitiké', _fwd, 'Eintracht Frankfurt', 2002, 'fr',
      foreignNewcomer: true),
  _p('20', 'Mario Götze', _mid, 'Eintracht Frankfurt', 1992, 'de'),
  // U20-Talente (für die Dynasty-Mechanik)
  _p('21', 'Assan Ouédraogo', _mid, 'RB Leipzig', 2006, 'de'),
  _p('22', 'Paris Brunner', _fwd, 'AS Monaco', 2006, 'de', foreignNewcomer: true),
  _p('23', 'Nestory Irankunda', _fwd, 'FC Bayern München', 2006, 'au',
      foreignNewcomer: true),
  _p('24', 'Max Moerstedt', _fwd, 'TSG Hoffenheim', 2005, 'de'),
];
