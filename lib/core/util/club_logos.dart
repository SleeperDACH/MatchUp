/// Bessere Vereinslogos: OpenLigaDBs `teamIconUrl` ist bei etlichen Clubs
/// problematisch — kaputt (JPG mit Hintergrund), veraltet oder ein
/// Wikimedia-Bild. Wikimedia **drosselt Hotlinking (HTTP 429)**, sodass Logos
/// last­abhängig ausfallen.
///
/// Fix: Für die betroffenen Vereine eine Override-URL vom hotlink-freundlichen
/// **TheSportsDB**-CDN (im Projekt ohnehin für den Spielerpool genutzt). Clubs
/// ohne Eintrag behalten ihr OpenLigaDB-Icon (meist stabile PNGs).
///
/// Schlüssel = kanonischer OpenLigaDB-Teamname.
library;

const _base = 'https://r2.thesportsdb.com/images/media/team/badge/';

const _overrides = <String, String>{
  '1. FC Köln': '${_base}2j1sc91566049407.png',
  'Borussia Dortmund': '${_base}tqo8ge1716960353.png',
  '1. FC Union Berlin': '${_base}q0o5001599679795.png',
  'SV Werder Bremen': '${_base}tkvqan1716960454.png',
  '1. FSV Mainz 05': '${_base}fhm9v51552134916.png',
  'FC Bayern München': '${_base}01ogkh1716960412.png',
  'SC Paderborn 07': '${_base}kddvva1566048058.png',
  'SV 07 Elversberg': '${_base}z079go1677573926.png',
};

/// Beste Logo-URL für [teamName] (kanonischer OpenLigaDB-Name); [openLigaUrl]
/// ist die vom Feed gelieferte Icon-URL (oder null).
String? clubLogoUrl(String teamName, String? openLigaUrl) =>
    _overrides[teamName] ?? openLigaUrl;
