/// Einheitliche Flaggen für Nationalteams über flagcdn.com.
///
/// Die Icon-URLs von OpenLigaDB sind für Nationalteams unbrauchbar
/// uneinheitlich (Wikimedia/UEFA/FIFA/Pixabay gemischt, teils kaputt).
/// Stattdessen: Teamkürzel → ISO-3166-alpha-2 → flagcdn-PNG.
///
/// Abgedeckt sind die Kürzel der WM 2026 (überwiegend ISO alpha-3)
/// plus gängige FIFA-Varianten (GER, SUI, POR, …) für künftige
/// Turniere. Unbekannte Kürzel (z. B. Platzhalter wie „Sieger Gruppe A")
/// geben null zurück — dann greift der Fallback im TeamBadge.
library;

const _countryCodes = <String, String>{
  // WM 2026 (Kürzel wie von OpenLigaDB geliefert)
  'ARG': 'ar', 'AUS': 'au', 'AUT': 'at', 'BEL': 'be', 'BIH': 'ba',
  'BRA': 'br', 'CAN': 'ca', 'CHE': 'ch', 'CIV': 'ci', 'COD': 'cd',
  'COL': 'co', 'CPV': 'cv', 'CUW': 'cw', 'CZE': 'cz', 'DEU': 'de',
  'DZA': 'dz', 'ECU': 'ec', 'EGY': 'eg', 'ENG': 'gb-eng', 'ESP': 'es',
  'FRA': 'fr', 'GHA': 'gh', 'HRV': 'hr', 'HTI': 'ht', 'IRN': 'ir',
  'IRQ': 'iq', 'JOR': 'jo', 'JPN': 'jp', 'KOR': 'kr', 'MAR': 'ma',
  'MEX': 'mx', 'NLD': 'nl', 'NOR': 'no', 'NZL': 'nz', 'PAN': 'pa',
  'PAR': 'py', 'PRT': 'pt', 'QAT': 'qa', 'RSA': 'za', 'SAU': 'sa',
  'SCT': 'gb-sct', 'SEN': 'sn', 'SWE': 'se', 'TUN': 'tn', 'TUR': 'tr',
  'URY': 'uy', 'USA': 'us', 'UZB': 'uz',
  // Gängige FIFA-Kürzel (EM, Quali, künftige Turniere)
  'GER': 'de', 'SUI': 'ch', 'POR': 'pt', 'NED': 'nl', 'CRO': 'hr',
  'SCO': 'gb-sct', 'WAL': 'gb-wls', 'NIR': 'gb-nir', 'IRL': 'ie',
  'POL': 'pl', 'DEN': 'dk', 'ITA': 'it', 'GRE': 'gr', 'SRB': 'rs',
  'SVK': 'sk', 'SVN': 'si', 'UKR': 'ua', 'ROU': 'ro', 'ISL': 'is',
  'FIN': 'fi', 'HUN': 'hu', 'BUL': 'bg', 'ALB': 'al', 'MKD': 'mk',
  'GEO': 'ge', 'CHI': 'cl', 'PER': 'pe', 'VEN': 've', 'BOL': 'bo',
  'CRC': 'cr', 'HON': 'hn', 'JAM': 'jm', 'NGA': 'ng', 'CMR': 'cm',
  'KSA': 'sa', 'UAE': 'ae',
};

/// PNG-URL einer runden darstellbaren Flagge (80 px breit) oder null,
/// wenn das Kürzel kein bekanntes Land ist.
String? countryFlagUrl(String teamShortName) {
  final iso = _countryCodes[teamShortName.toUpperCase()];
  return iso == null ? null : 'https://flagcdn.com/w80/$iso.png';
}
