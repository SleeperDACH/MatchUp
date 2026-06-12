/// Übersetzt die (englischen) Teamnamen der Quoten-Quelle auf die
/// stabilen Kürzel, die OpenLigaDB als `shortName` führt — für die WM die
/// FIFA-3-Letter-Codes (BRA, MAR, CHE …). So matcht ein Quoten-Eintrag
/// zuverlässig auf ein Fixture, ohne sich auf identische Klarnamen zu
/// verlassen.
abstract final class OddsTeamResolver {
  /// Liefert den OpenLigaDB-`shortName` zum Quoten-Teamnamen oder `null`,
  /// wenn der Wettbewerb/Name nicht bekannt ist.
  static String? codeFor(String sportKey, String oddsTeamName) {
    final norm = _normalize(oddsTeamName);
    switch (sportKey) {
      case 'soccer_fifa_world_cup':
        return _worldCup[norm];
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
}
