/// **Was beim Nachtragen eines Spieltags gespeichert wird.**
///
/// Die Regel steht als reine Funktion da, weil sie eine Entscheidung ist und
/// keine Anzeige: Welche der eingetippten Zeilen gehen überhaupt an den
/// Server? Vorher trug jede Zeile ihren eigenen Speichern-Knopf, und die
/// Antwort war trivial — „die eine, auf die du getippt hast". Mit einem Knopf
/// je Spieltag ist sie es nicht mehr.
library;

/// Eine Zeile des Nachtrag-Schirms, so wie sie im Formular steht.
class NachtragZeile {
  const NachtragZeile({
    required this.fixtureId,
    required this.heim,
    required this.gast,
    this.vorherHeim,
    this.vorherGast,
  });

  final String fixtureId;

  /// Der rohe Feldinhalt — leer, solange nichts eingetippt wurde.
  final String heim;
  final String gast;

  /// Was für dieses Spiel schon gespeichert ist. `null` = noch kein Tipp.
  final int? vorherHeim;
  final int? vorherGast;
}

/// Ein fertig geprüfter Tipp, bereit für die Sammel-RPC.
typedef NachtragTipp = ({String fixtureId, int home, int away});

/// Das Ergebnis der Prüfung: was gespeichert wird, und was im Weg steht.
class NachtragPruefung {
  const NachtragPruefung({
    required this.zuSpeichern,
    required this.halbeZeilen,
    required this.unveraendert,
  });

  /// Vollständig ausgefüllte Zeilen, deren Wert sich geändert hat.
  final List<NachtragTipp> zuSpeichern;

  /// **Halb ausgefüllte Zeilen** — eine Zahl steht, die andere fehlt.
  ///
  /// Sie sind der Grund, warum diese Prüfung überhaupt existiert: Wer neun
  /// Spiele tippt und bei einem die zweite Zahl vergisst, bekäme sonst ein
  /// stilles „gespeichert" und einen fehlenden Tipp. Der Schirm nennt sie
  /// beim Namen, statt sie zu überspringen.
  final List<String> halbeZeilen;

  /// Zeilen, die schon genau so gespeichert sind. Sie noch einmal zu
  /// schreiben wäre harmlos, aber der Knopf soll ehrlich sagen, wie viele
  /// Tipps er wirklich anfasst.
  final int unveraendert;

  bool get hatFehler => halbeZeilen.isNotEmpty;
  bool get gibtEsWasZuTun => zuSpeichern.isNotEmpty;
}

/// Prüft die Zeilen eines Spieltags.
///
/// **Leer heißt „nicht getippt", nicht „0:0".** Eine leere Zeile wird
/// übersprungen; nur wer beide Felder füllt, tippt. Wer genau ein Feld füllt,
/// hat sich vertan — das ist ein Fehler und kein Überspringen.
NachtragPruefung pruefeNachtrag(Iterable<NachtragZeile> zeilen) {
  final tipps = <NachtragTipp>[];
  final halbe = <String>[];
  var unveraendert = 0;

  for (final z in zeilen) {
    final h = z.heim.trim();
    final a = z.gast.trim();
    if (h.isEmpty && a.isEmpty) continue;
    if (h.isEmpty || a.isEmpty) {
      halbe.add(z.fixtureId);
      continue;
    }
    final hz = int.tryParse(h);
    final az = int.tryParse(a);
    if (hz == null || az == null) {
      halbe.add(z.fixtureId);
      continue;
    }
    if (hz == z.vorherHeim && az == z.vorherGast) {
      unveraendert++;
      continue;
    }
    tipps.add((fixtureId: z.fixtureId, home: hz, away: az));
  }

  return NachtragPruefung(
    zuSpeichern: tipps,
    halbeZeilen: halbe,
    unveraendert: unveraendert,
  );
}
