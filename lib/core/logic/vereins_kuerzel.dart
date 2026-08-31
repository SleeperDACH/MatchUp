/// **Das Kürzel, unter dem ein Verein bekannt ist** — FCB, BVB, S04.
///
/// Aus dem Namen abgeleitet käme „FB" für den FC Bayern heraus (die
/// Anfangsbuchstaben der ersten beiden Wörter) und „BM" für Mönchengladbach.
/// Beides erkennt niemand. Die geläufigen Kürzel sind gewachsen, nicht
/// gebildet, und stehen deshalb als Tabelle da.
///
/// Verglichen wird die **kanonische Form** des Namens: ohne Ziffern, Punkte
/// und Vereinsformen. Damit trifft ein Eintrag beide Schreibweisen, die in
/// dieser App vorkommen — „1. FSV Mainz 05" aus den Kadern und „FSV Mainz 05"
/// aus dem Sportmonks-Spielplan. Dieselbe Regel wie serverseitig in
/// `fantasy_verein_kanonisch` (Migration 0108); dass die beiden Quellen
/// verschieden schreiben, hat dort schon einmal eine Woche gekostet.
library;

const _kuerzel = <String, String>{
  'bayern münchen': 'FCB',
  'borussia dortmund': 'BVB',
  'rb leipzig': 'RBL',
  'bayer leverkusen': 'B04',
  'stuttgart': 'VFB',
  'eintracht frankfurt': 'SGE',
  'werder bremen': 'SVW',
  'augsburg': 'FCA',
  'hoffenheim': 'TSG',
  'freiburg': 'SCF',
  'mainz': 'M05',
  'köln': 'KÖL',
  'union berlin': 'FCU',
  'hamburger': 'HSV',
  'borussia mönchengladbach': 'BMG',
  'st pauli': 'STP',
  'heidenheim': 'FCH',
  'elversberg': 'SVE',
  'schalke': 'S04',
  'paderborn': 'SCP',
  'wolfsburg': 'WOB',
  'bochum': 'BOC',
  'holstein kiel': 'KSV',
  'nürnberg': 'FCN',
  'hannover': 'H96',
  'fortuna düsseldorf': 'F95',
  'karlsruher': 'KSC',
  'hertha': 'BSC',
  'darmstadt': 'SVD',
  'greuther fürth': 'SGF',
  'kaiserslautern': 'FCK',
  'magdeburg': 'FCM',
  'braunschweig': 'BTSV',
  'münster': 'SCP',
  'regensburg': 'SSV',
  'ulm': 'SSV',
};

/// Kanonische Form eines Vereinsnamens: klein, ohne Ziffern und Punkte, ohne
/// die Vereinsformen (FC, SV, SC, …).
String vereinKanonisch(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[0-9.]'), '')
    .replaceAll(
        RegExp(r'(^|\s)(fc|sv|sc|tsg|vfb|vfl|fsv|tsv|bsc|spvgg|msv|kfc)(\s|$)'),
        ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Kürzel eines Vereins — aus der Tabelle, sonst abgeleitet.
///
/// Die Ableitung ist der Notnagel für Vereine, die wir nicht kennen (zweite
/// Liga, Aufsteiger, ausländische Klubs im Kader): die ersten drei Buchstaben
/// des kennzeichnenden Wortes. „?" gibt es nur für einen leeren Namen.
String vereinsKuerzel(String name) {
  final k = vereinKanonisch(name);
  if (k.isEmpty) return '?';
  final treffer = _kuerzel[k];
  if (treffer != null) return treffer;
  for (final MapEntry(key: schluessel, value: kurz) in _kuerzel.entries) {
    if (k.contains(schluessel)) return kurz;
  }
  // **Das längste Wort, nicht das erste.** „AS Monaco" ergäbe sonst „AS" —
  // der Ortsname ist das, woran man einen Verein erkennt, nicht die
  // Rechtsform davor.
  final woerter = k.split(' ')..sort((a, b) => b.length.compareTo(a.length));
  final wort = woerter.first;
  return wort.substring(0, wort.length < 3 ? wort.length : 3).toUpperCase();
}
