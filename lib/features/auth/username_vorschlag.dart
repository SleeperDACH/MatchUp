/// Nutzernamen für Konten, die über Google oder Apple hereinkommen.
///
/// Reines Dart ohne Abhängigkeiten — die Regeln sind die der Tabelle
/// `profiles`: 3 bis 24 Zeichen, eindeutig. Wer beides nicht einhält, bekommt
/// keinen Fehler in der Oberfläche, sondern eine abgelehnte Einfügung tief im
/// Anmeldevorgang, und der Nutzer steht angemeldet und namenlos da.
library;

/// Kürzeste und längste erlaubte Länge laut `profiles`-Constraint.
const int minNutzernameLaenge = 3;
const int maxNutzernameLaenge = 24;

/// Sucht den ersten brauchbaren Namen aus dem, was der Anbieter mitgibt.
///
/// Reihenfolge nach Verlässlichkeit: was der Anbieter **jetzt** gerade
/// geliefert hat ([bevorzugt] — bei Apple der einzige Moment, in dem es je
/// einen Namen gibt), dann die Metadaten der Sitzung, zuletzt der Teil vor dem
/// `@` der E-Mail. Bleibt nichts übrig, „Tipper" — ein Platzhalter, den man
/// ändern will, ist besser als ein leeres Feld, das man ändern muss.
String nutzernameVorschlag({
  String? bevorzugt,
  Map<String, dynamic>? metadaten,
  String? email,
}) {
  final daten = metadaten ?? const <String, dynamic>{};
  final kandidaten = <String?>[
    bevorzugt,
    daten['full_name'] as String?,
    daten['name'] as String?,
    daten['preferred_username'] as String?,
    email?.split('@').first,
  ];
  for (final kandidat in kandidaten) {
    final sauber = nutzernameKuerzen(kandidat);
    if (sauber != null) return sauber;
  }
  return 'Tipper';
}

/// Leerraum zusammenziehen, auf [maxNutzernameLaenge] kappen.
///
/// `null`, wenn danach weniger als [minNutzernameLaenge] Zeichen übrig sind —
/// „Bo" ist ein echter Vorname und trotzdem kein gültiger Eintrag, dann greift
/// der nächste Kandidat.
String? nutzernameKuerzen(String? roh) {
  if (roh == null) return null;
  final sauber = roh.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (sauber.length < minNutzernameLaenge) return null;
  if (sauber.length <= maxNutzernameLaenge) return sauber;
  // Nach dem Kappen kann ein Leerzeichen am Ende stehen; das wäre ein Name
  // mit unsichtbarem Rest.
  final gekappt = sauber.substring(0, maxNutzernameLaenge).trimRight();
  return gekappt.length < minNutzernameLaenge ? null : gekappt;
}

/// Hängt [anhang] an [basis], ohne die Längengrenze zu reißen — die Basis
/// weicht, nicht die Unterscheidung. „Michael Müller" wird zu „Michael Mülle2"
/// und nicht zu einem zweiten „Michael Müller", der die Einfügung erneut
/// scheitern ließe.
String nutzernameMitAnhang(String basis, String anhang) {
  final platz = maxNutzernameLaenge - anhang.length;
  if (platz <= 0) return anhang.substring(0, maxNutzernameLaenge);
  final kurz = basis.length <= platz ? basis : basis.substring(0, platz);
  return '${kurz.trimRight()}$anhang';
}
