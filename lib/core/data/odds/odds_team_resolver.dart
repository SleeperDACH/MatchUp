/// Übersetzt die (englischen) Teamnamen der Quoten-Quelle auf die
/// stabilen Kürzel, die OpenLigaDB als `shortName` führt — für die WM die
/// FIFA-3-Letter-Codes (BRA, MAR, CHE …). So matcht ein Quoten-Eintrag
/// zuverlässig auf ein Fixture, ohne sich auf identische Klarnamen zu
/// verlassen.
abstract final class OddsTeamResolver {
  /// Kanonischer Code zum Quoten-Teamnamen oder `null`, wenn der Wettbewerb/
  /// Name nicht bekannt ist. WM → FIFA-Code; 1./2. Bundesliga → Sportmonks-
  /// Team-ID (die Fixtures dieser Ligen kommen aus Sportmonks).
  static String? codeFor(String sportKey, String oddsTeamName) {
    final norm = _normalize(oddsTeamName);
    switch (sportKey) {
      case 'soccer_fifa_world_cup':
        return _worldCup[norm];
      case 'soccer_germany_bundesliga':
        return _bundesliga[norm];
      case 'soccer_germany_bundesliga2':
        return _bundesliga2[norm];
      default:
        return null;
    }
  }

  /// Kanonischer Code eines **Fixture-Teams** (Gegenstück zu [codeFor]).
  /// WM: der OpenLigaDB-`shortName` (= FIFA-Code); Bundesligen: die
  /// Sportmonks-Team-ID aus der qualifizierten Fixture-Team-ID
  /// (`sportmonks:503` → `503`).
  static String? fixtureCodeFor(String sportKey, String teamId, String shortName) {
    switch (sportKey) {
      case 'soccer_fifa_world_cup':
        return shortName;
      case 'soccer_germany_bundesliga':
      case 'soccer_germany_bundesliga2':
        return teamId.startsWith('sportmonks:')
            ? teamId.split(':').last
            : null;
      default:
        return null;
    }
  }

  /// Kleinbuchstaben, Akzente entfernt, nur Buchstaben/Ziffern + einzelne
  /// Leerzeichen — robust gegen Schreibvarianten der Buchmacher.
  static String _normalize(String s) {
    final folded = _foldDiacritics(s.toLowerCase());
    final cleaned = folded.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return cleaned.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _foldDiacritics(String s) {
    const map = {
      'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'ç': 'c',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y',
    };
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Quoten-Name (normalisiert) → OpenLigaDB-shortName. Mehrere Schreib-
  /// varianten je Land sind absichtlich enthalten (Buchmacher uneinheitlich).
  static const Map<String, String> _worldCup = {
    'algeria': 'DZA',
    'argentina': 'ARG',
    'australia': 'AUS',
    'austria': 'AUT',
    'belgium': 'BEL',
    'bosnia herzegovina': 'BIH',
    'bosnia and herzegovina': 'BIH',
    'brazil': 'BRA',
    'canada': 'CAN',
    'cape verde': 'CPV',
    'cabo verde': 'CPV',
    'colombia': 'COL',
    'croatia': 'HRV',
    'curacao': 'CUW',
    'czech republic': 'CZE',
    'czechia': 'CZE',
    'dr congo': 'COD',
    'congo dr': 'COD',
    'democratic republic of congo': 'COD',
    'ecuador': 'ECU',
    'egypt': 'EGY',
    'england': 'ENG',
    'france': 'FRA',
    'germany': 'DEU',
    'ghana': 'GHA',
    'haiti': 'HTI',
    'iran': 'IRN',
    'ir iran': 'IRN',
    'iraq': 'IRQ',
    'ivory coast': 'CIV',
    'cote divoire': 'CIV',
    'japan': 'JPN',
    'jordan': 'JOR',
    'mexico': 'MEX',
    'morocco': 'MAR',
    'netherlands': 'NLD',
    'new zealand': 'NZL',
    'norway': 'NOR',
    'panama': 'PAN',
    'paraguay': 'PAR',
    'portugal': 'PRT',
    'qatar': 'QAT',
    'saudi arabia': 'SAU',
    'scotland': 'SCT',
    'senegal': 'SEN',
    'south africa': 'RSA',
    'south korea': 'KOR',
    'korea republic': 'KOR',
    'spain': 'ESP',
    'sweden': 'SWE',
    'switzerland': 'CHE',
    'tunisia': 'TUN',
    'turkey': 'TUR',
    'turkiye': 'TUR',
    'usa': 'USA',
    'united states': 'USA',
    'uruguay': 'URY',
    'uzbekistan': 'UZB',
  };

  /// the-odds-api-Name (normalisiert) → Sportmonks-Team-ID (Bundesliga).
  /// Mehrere gängige Schreibvarianten je Verein.
  static const Map<String, String> _bundesliga = {
    'bayern munich': '503', 'bayern munchen': '503', 'fc bayern munchen': '503',
    'borussia dortmund': '68', 'dortmund': '68',
    'rb leipzig': '277', 'leipzig': '277',
    'bayer leverkusen': '3321', 'bayer 04 leverkusen': '3321', 'leverkusen': '3321',
    'eintracht frankfurt': '366', 'frankfurt': '366',
    'vfb stuttgart': '3319', 'stuttgart': '3319',
    'sc freiburg': '3543', 'freiburg': '3543',
    'werder bremen': '82', 'bremen': '82',
    'augsburg': '90', 'fc augsburg': '90',
    'union berlin': '1079', '1 fc union berlin': '1079', 'fc union berlin': '1079',
    'tsg hoffenheim': '2726', 'hoffenheim': '2726', '1899 hoffenheim': '2726',
    '1 fc koln': '3320', 'fc koln': '3320', 'koln': '3320', 'fc cologne': '3320',
    'cologne': '3320',
    'fsv mainz 05': '794', 'mainz': '794', 'mainz 05': '794', '1 fsv mainz 05': '794',
    'borussia monchengladbach': '683', 'monchengladbach': '683',
    'gladbach': '683',
    'hamburger sv': '2708', 'hamburg': '2708', 'hamburger sv hamburg': '2708',
    'sc paderborn': '2642', 'paderborn': '2642', 'sc paderborn 07': '2642',
    'fc schalke 04': '67', 'schalke 04': '67', 'schalke': '67',
    'elversberg': '3588', 'sv elversberg': '3588',
  };

  /// the-odds-api-Name (normalisiert) → Sportmonks-Team-ID (2. Bundesliga).
  static const Map<String, String> _bundesliga2 = {
    '1 fc heidenheim': '2831', 'heidenheim': '2831',
    '1 fc kaiserslautern': '1638', 'kaiserslautern': '1638',
    '1 fc magdeburg': '3527', 'magdeburg': '3527',
    '1 fc nurnberg': '956', 'nurnberg': '956', 'nuremberg': '956',
    'arminia bielefeld': '2927', 'bielefeld': '2927', 'dsc arminia bielefeld': '2927',
    'dynamo dresden': '1077', 'dresden': '1077', 'sg dynamo dresden': '1077',
    'eintracht braunschweig': '3565', 'braunschweig': '3565',
    'fc energie cottbus': '3322', 'energie cottbus': '3322', 'cottbus': '3322',
    'fc st pauli': '353', 'st pauli': '353', 'st. pauli': '353',
    'greuther furth': '3431', 'furth': '3431', 'spvgg greuther furth': '3431',
    'hannover 96': '2554', 'hannover': '2554', 'hanover 96': '2554',
    'hertha berlin': '3317', 'hertha bsc': '3317', 'hertha': '3317',
    'holstein kiel': '3611', 'kiel': '3611',
    'karlsruher sc': '3114', 'karlsruhe': '3114', 'karlsruher sc karlsruhe': '3114',
    'sv darmstadt 98': '482', 'darmstadt': '482', 'darmstadt 98': '482',
    'vfl bochum': '999', 'bochum': '999', 'vfl bochum 1848': '999',
    'vfl osnabruck': '2872', 'osnabruck': '2872',
    'vfl wolfsburg': '510', 'wolfsburg': '510',
  };
}
