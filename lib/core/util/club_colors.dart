import 'dart:ui' show Color;

/// Trikotfarben eines Vereins.
///
/// [primary] ist die Grundfarbe des Trikots, [secondary] die der Ärmel und des
/// Kragens. Beides sind Heimtrikot-Farben — Auswärtstrikots wechseln je Saison
/// und liefert kein Feed, den wir haben.
class ClubColors {
  const ClubColors(this.primary, this.secondary);
  final Color primary;
  final Color secondary;
}

const _weiss = Color(0xFFF2F4F8);
const _schwarz = Color(0xFF15171E);

/// Heimtrikot-Farben je Verein.
///
/// Schlüssel ist ein **unterscheidender Namensbestandteil** in Kleinschrift,
/// kein vollständiger Vereinsname: Die Quellen schreiben denselben Klub mal
/// „1. FC Nürnberg", mal „Nürnberg", mal „FCN". Gesucht wird deshalb über
/// [clubColors] mit Wort-Tokens, nicht über Gleichheit.
///
/// Sportmonks liefert in diesem Tarif keine Vereinsfarben — die Liste ist von
/// Hand gepflegt. Unbekannte Vereine bekommen die Ausweichfarbe aus
/// [clubColors]; das ist kein Fehler, sondern der Normalfall für Klubs
/// außerhalb der drei Ligen.
const _farben = <String, ClubColors>{
  // 1. Bundesliga
  'bayern': ClubColors(Color(0xFFDC052D), _weiss),
  'dortmund': ClubColors(Color(0xFFFDE100), _schwarz),
  'leipzig': ClubColors(_weiss, Color(0xFFDD0741)),
  'leverkusen': ClubColors(Color(0xFFE32221), _schwarz),
  'monchengladbach': ClubColors(_weiss, Color(0xFF00A551)),
  'gladbach': ClubColors(_weiss, Color(0xFF00A551)),
  'frankfurt': ClubColors(_schwarz, Color(0xFFE1000F)),
  'stuttgart': ClubColors(_weiss, Color(0xFFE32219)),
  'freiburg': ClubColors(Color(0xFF000000), Color(0xFFE2001A)),
  'hoffenheim': ClubColors(Color(0xFF1C63B7), _weiss),
  'augsburg': ClubColors(Color(0xFFBA3733), Color(0xFF46714D)),
  'koln': ClubColors(_weiss, Color(0xFFED1C24)),
  'mainz': ClubColors(Color(0xFFC3141E), _weiss),
  'union': ClubColors(Color(0xFFEB1923), Color(0xFFFFE500)),
  'bremen': ClubColors(Color(0xFF1D9053), _weiss),
  'werder': ClubColors(Color(0xFF1D9053), _weiss),
  'hamburger': ClubColors(_weiss, Color(0xFF0A3A82)),
  'hsv': ClubColors(_weiss, Color(0xFF0A3A82)),
  'schalke': ClubColors(Color(0xFF004D9D), _weiss),
  'elversberg': ClubColors(Color(0xFF00A2E1), _weiss),
  'paderborn': ClubColors(Color(0xFF004E9E), _weiss),

  // 2. Bundesliga
  'hertha': ClubColors(Color(0xFF004D9E), _weiss),
  'pauli': ClubColors(Color(0xFF614C3E), _weiss),
  'nurnberg': ClubColors(Color(0xFF8F0B26), _weiss),
  'bochum': ClubColors(Color(0xFF005CA9), _weiss),
  'dresden': ClubColors(Color(0xFFFFE500), _schwarz),
  'kaiserslautern': ClubColors(Color(0xFFE30613), _weiss),
  'hannover': ClubColors(Color(0xFF00963F), _weiss),
  'darmstadt': ClubColors(Color(0xFF004E9E), _weiss),
  'wolfsburg': ClubColors(Color(0xFF65B32E), _weiss),
  'heidenheim': ClubColors(Color(0xFFE30613), Color(0xFF0B3D91)),
  'osnabruck': ClubColors(Color(0xFF7B2B2B), _weiss),
  'holstein': ClubColors(Color(0xFF0A2A5E), _weiss),
  'kiel': ClubColors(Color(0xFF0A2A5E), _weiss),
  'karlsruher': ClubColors(Color(0xFF004E9E), _weiss),
  'ksc': ClubColors(Color(0xFF004E9E), _weiss),
  'bielefeld': ClubColors(_weiss, Color(0xFF004E9E)),
  'arminia': ClubColors(_weiss, Color(0xFF004E9E)),
  'magdeburg': ClubColors(Color(0xFF004E9E), _weiss),
  'braunschweig': ClubColors(Color(0xFFFFE500), Color(0xFF004E9E)),
  'furth': ClubColors(_weiss, Color(0xFF00975F)),
  'cottbus': ClubColors(Color(0xFFE30613), _weiss),

  // 3. Liga (Auswahl)
  'waldhof': ClubColors(Color(0xFF005CA9), _weiss),
  'fortuna': ClubColors(_weiss, Color(0xFFE30613)),
  'dusseldorf': ClubColors(_weiss, Color(0xFFE30613)),
  'duisburg': ClubColors(Color(0xFF004E9E), _weiss),
  'rostock': ClubColors(Color(0xFF004E9E), _weiss),
  'saarbrucken': ClubColors(Color(0xFF004E9E), _weiss),
  'essen': ClubColors(Color(0xFFE30613), _weiss),
  'aachen': ClubColors(Color(0xFFFFE500), _schwarz),
  'ingolstadt': ClubColors(Color(0xFFE30613), _weiss),
  'verl': ClubColors(Color(0xFF005CA9), _weiss),
  'meppen': ClubColors(Color(0xFF004E9E), _weiss),
  'wurzburger': ClubColors(Color(0xFFE30613), _weiss),
};

/// Wörter, die keinen Verein unterscheiden — dieselbe Logik wie bei der
/// Vereinssuche: Ohne sie würde „Borussia Dortmund" auf „Borussia
/// Mönchengladbach" passen.
const _ballast = {
  'fc', 'sv', 'sc', 'vfb', 'vfl', 'tsg', 'fsv', 'rb', 'sg', 'tsv', 'bv',
  'msv', 'dsc', 'spvgg', 'borussia', 'eintracht', 'alemannia', 'energie',
  'dynamo', 'hansa', 'rot', 'weiss', 'ii', '1', '04', '05', '07', '09',
  '96', '98', '1846', '1848', '1899', '1900',
};

String _falte(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

/// Trikotfarben für [teamName]; [fallback] greift, wenn der Verein nicht in
/// der Liste steht (etwa Amateur- oder Auslandsklubs im Pokal).
ClubColors clubColors(String teamName, {required ClubColors fallback}) {
  final tokens = _falte(teamName)
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(' ')
      .where((t) => t.isNotEmpty && !_ballast.contains(t));
  for (final t in tokens) {
    final treffer = _farben[t];
    if (treffer != null) return treffer;
  }
  return fallback;
}

/// Schrift auf dem Trikot: dunkel auf hellem Stoff, hell auf dunklem.
Color jerseyTextColor(Color jersey) =>
    jersey.computeLuminance() > 0.45 ? _schwarz : _weiss;
