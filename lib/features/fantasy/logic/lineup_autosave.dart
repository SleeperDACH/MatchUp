/// Was der Auto-Speicher der Aufstellung als Nächstes tun soll.
///
/// Die Entscheidung stand als Bedingung in einem Timer-Rückruf:
///
/// ```dart
/// if (mounted && _valid && !_saving) _save(_effRound, _lastIds);
/// ```
///
/// Drei Ausgänge, und zwei davon waren endgültig und stumm — die Änderung war
/// weg, während die Fußzeile „Änderungen werden automatisch gespeichert"
/// versprach. Als Bedingung im UI-Code ließ sich das nicht prüfen; als reine
/// Funktion schon.
library;

/// Der nächste Schritt des Auto-Speicherns.
enum SpeicherSchritt {
  /// Jetzt an den Server schicken.
  speichern,

  /// Gleich noch einmal versuchen (etwas ist gerade unterwegs oder fehlt).
  spaeterErneut,

  /// Nichts tun und das auch anzeigen — die Elf ist unvollständig, der Server
  /// nähme sie ohnehin nicht an.
  unvollstaendig,
}

/// Entscheidet, was mit einer offenen Änderung geschehen soll.
///
/// * [gueltig] — ergibt die Aufstellung eine erlaubte Formation?
/// * [laeuftGerade] — ist schon ein Speichern unterwegs? Dann **nicht**
///   verwerfen: Genau so ging die zweite von zwei schnellen Änderungen
///   verloren.
/// * [spieltag] — `null`, solange der aktuelle Spieltag noch lädt. Dann warten
///   statt raten: Der frühere Notnagel `?? 34` hat eine Aufstellung
///   nachweislich auf Spieltag 34 geschrieben.
SpeicherSchritt naechsterSpeicherSchritt({
  required bool gueltig,
  required bool laeuftGerade,
  required int? spieltag,
}) {
  if (laeuftGerade) return SpeicherSchritt.spaeterErneut;
  if (!gueltig) return SpeicherSchritt.unvollstaendig;
  if (spieltag == null) return SpeicherSchritt.spaeterErneut;
  return SpeicherSchritt.speichern;
}
