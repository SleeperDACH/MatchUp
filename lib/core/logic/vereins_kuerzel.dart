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

/// **Der eine Name, unter dem ein Verein in einer Spielpaarung steht** —
/// „Bayern", „Schalke", „Gladbach", sonst die Stadt: „Hamburg", „Köln",
/// „Frankfurt", „St. Pauli" (auf Ansage, 16.10.2026).
///
/// Wie bei den Kürzeln ist das gewachsen, nicht gebildet: Schalke heißt nicht
/// „Gelsenkirchen", Union nicht „Berlin", der HSV nicht „Hamburger". Deshalb
/// eine Tabelle über die kanonische Form, mit derselben Begründung wie
/// [vereinsKuerzel] — beide Schreibweisen dieser App treffen denselben
/// Eintrag. Unbekannte Namen (Pokalgegner, Nationalteams) bleiben, wie sie
/// sind; ein geratener Kurzname wäre schlimmer als ein langer.
///
/// Frauenteams tragen bei Sportmonks ein „ W" — es fällt weg, der Wettbewerb
/// sagt es schon. Zweite Mannschaften behalten ihr „II".
const _kurznamen = <String, String>{
  'bayern münchen': 'Bayern',
  'borussia dortmund': 'Dortmund',
  'rb leipzig': 'Leipzig',
  'bayer leverkusen': 'Leverkusen',
  'stuttgart': 'Stuttgart',
  'eintracht frankfurt': 'Frankfurt',
  'werder bremen': 'Bremen',
  'augsburg': 'Augsburg',
  'hoffenheim': 'Hoffenheim',
  'freiburg': 'Freiburg',
  'mainz': 'Mainz',
  'köln': 'Köln',
  'union berlin': 'Union',
  'hamburger': 'Hamburg',
  'borussia mönchengladbach': 'Gladbach',
  'st pauli': 'St. Pauli',
  'heidenheim': 'Heidenheim',
  'elversberg': 'Elversberg',
  'schalke': 'Schalke',
  'paderborn': 'Paderborn',
  'wolfsburg': 'Wolfsburg',
  'bochum': 'Bochum',
  'holstein kiel': 'Kiel',
  'nürnberg': 'Nürnberg',
  'hannover': 'Hannover',
  'fortuna düsseldorf': 'Düsseldorf',
  'karlsruher': 'Karlsruhe',
  'hertha': 'Hertha',
  'darmstadt': 'Darmstadt',
  'greuther fürth': 'Fürth',
  'kaiserslautern': 'Kaiserslautern',
  'magdeburg': 'Magdeburg',
  'eintracht braunschweig': 'Braunschweig',
  'preußen münster': 'Münster',
  'jahn regensburg': 'Regensburg',
  'ulm': 'Ulm',
  'dsc arminia bielefeld': 'Bielefeld',
  'arminia bielefeld': 'Bielefeld',
  'dynamo dresden': 'Dresden',
  'hansa rostock': 'Rostock',
  'saarbrücken': 'Saarbrücken',
  'wehen wiesbaden': 'Wiesbaden',
  'erzgebirge aue': 'Aue',
  'rot-weiss essen': 'Essen',
  'waldhof mannheim': 'Mannheim',
  'energie cottbus': 'Cottbus',
  'osnabrück': 'Osnabrück',
  'ingolstadt': 'Ingolstadt',
  'verl': 'Verl',
  'duisburg': 'Duisburg',
  'alemannia aachen': 'Aachen',
  'viktoria köln': 'Viktoria',
  'fortuna köln': 'Fortuna',
  'hallescher': 'Halle',
  'carl zeiss jena': 'Jena',
  'würzburger kickers': 'Würzburg',
  'eintracht trier': 'Trier',
  'phönix lübeck': 'Lübeck',
  'sonnenhof großaspach': 'Großaspach',
  'bahlinger': 'Bahlingen',
  'westfalia rhynern': 'Rhynern',
  'schott mainz': 'Schott',
  'st tönis': 'St. Tönis',
  // Rückfall für abgekürzte Schreibweisen („Bor. Mönchengladbach",
  // „Bor. Dortmund") — sie treffen über das „enthält" unten.
  'mönchengladbach': 'Gladbach',
  'dortmund': 'Dortmund',
  'leverkusen': 'Leverkusen',
  'leipzig': 'Leipzig',
  'frankfurt': 'Frankfurt',
  'bremen': 'Bremen',
};

String vereinsKurzname(String name) {
  var roh = name.trim();
  if (roh.isEmpty) return roh;
  // 1860 München: Die Ziffern sind der Name — die kanonische Form wirft sie
  // weg und ließe nur „München" übrig.
  if (roh.contains('1860')) return '1860';
  // Frauen: „Bayer Leverkusen W" → „Leverkusen".
  if (roh.endsWith(' W')) roh = roh.substring(0, roh.length - 2).trim();
  // Zweite Mannschaft: „Hoffenheim II" → „Hoffenheim II".
  var zusatz = '';
  if (roh.endsWith(' II')) {
    zusatz = ' II';
    roh = roh.substring(0, roh.length - 3).trim();
  }
  final k = vereinKanonisch(roh);
  final treffer = _kurznamen[k];
  if (treffer != null) return '$treffer$zusatz';
  // Enthalten, längster Schlüssel zuerst — „viktoria köln" darf nicht als
  // „Köln" enden, nur weil „köln" auch passt.
  final schluessel = _kurznamen.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final s in schluessel) {
    if (k.contains(s)) return '${_kurznamen[s]}$zusatz';
  }
  return '$roh$zusatz';
}
