// Kurznamen der Vereine für Push-Meldungen (27.10.2026, auf Ansage: „bei den
// Push-Benachrichtigungen bitte auch die Kurznamen der Vereine verwenden, wie
// wir sie in der App haben").
//
// **Dieselbe Regel wie `vereinsKurzname` in
// `lib/core/logic/vereins_kuerzel.dart`** — Tabelle, kanonische Form, „enthält"
// mit dem längsten Schlüssel zuerst, Frauen ohne „ W", zweite Mannschaften mit
// „II", 1860 bleibt 1860. `test/push_kurznamen_test.dart` vergleicht beide
// Tabellen; wer eine ändert, ändert die andere mit.

export const KURZNAMEN: Record<string, string> = {
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
  'mönchengladbach': 'Gladbach',
  'dortmund': 'Dortmund',
  'leverkusen': 'Leverkusen',
  'leipzig': 'Leipzig',
  'frankfurt': 'Frankfurt',
  'bremen': 'Bremen',
};

export function vereinKanonisch(name: string): string {
  return name
    .toLowerCase()
    .replace(/[0-9.]/g, "")
    .replace(/(^|\s)(fc|sv|sc|tsg|vfb|vfl|fsv|tsv|bsc|spvgg|msv|kfc)(?=\s|$)/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const SCHLUESSEL = Object.keys(KURZNAMEN).sort((a, b) => b.length - a.length);

export function vereinsKurzname(name: string): string {
  let roh = name.trim();
  if (!roh) return roh;
  if (roh.includes("1860")) return "1860";
  if (roh.endsWith(" W")) roh = roh.slice(0, -2).trim();
  let zusatz = "";
  if (roh.endsWith(" II")) {
    zusatz = " II";
    roh = roh.slice(0, -3).trim();
  }
  const k = vereinKanonisch(roh);
  const treffer = KURZNAMEN[k];
  if (treffer) return treffer + zusatz;
  for (const s of SCHLUESSEL) {
    if (k.includes(s)) return KURZNAMEN[s] + zusatz;
  }
  return roh + zusatz;
}
