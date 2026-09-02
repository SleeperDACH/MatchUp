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

/// Wie lange nach einem **fehlgeschlagenen** Speichern gewartet wird, bevor es
/// der Schirm noch einmal versucht.
///
/// Gemeldet nach dem Spieltag: *„Während des letzten Spieltages gab es
/// häufiger Speicherprobleme bei der Aufstellung."*
///
/// Der Fehlschlag war die **einzige** Stelle im Auto-Speicher ohne zweiten
/// Versuch. `laeuftGerade` bestellt sich neu ein, `spieltag == null` auch —
/// nur ein Netzfehler zeigte eine Snackbar und war dann fertig. Genau der
/// Fall, der an einem Samstagnachmittag im Stadion mit einem Balken Empfang
/// auftritt: Der Zug ist im Schirm zu sehen, aber nirgends gespeichert.
///
/// Wachsender Abstand, damit ein länger weggebrochenes Netz nicht im
/// Sekundentakt angefunkt wird, gedeckelt bei 30 s, damit ein
/// wiedergekehrtes Netz nicht minutenlang ungenutzt bleibt.
Duration wartezeitNachFehler(int fehlversuche) {
  const kappe = Duration(seconds: 30);
  if (fehlversuche < 1) return Duration.zero;
  // Gedeckelt, bevor verschoben wird: Ein Schirm, der eine Viertelstunde
  // offen liegt und kein Netz hat, käme sonst in Zahlenbereiche, in denen die
  // Verschiebung kippt — und aus der Wartezeit würde eine negative Dauer.
  final n = fehlversuche.clamp(1, 8);
  final sekunden = 2 << (n - 1); // 2, 4, 8, 16, 32 …
  return sekunden >= kappe.inSeconds ? kappe : Duration(seconds: sekunden);
}

/// Was die Fußzeile über den Speicherstand sagt.
enum SpeicherAnzeige {
  /// Die Elf ist nicht vollständig — es *kann* nichts gespeichert werden.
  unvollstaendig,

  /// Der letzte Versuch ist gescheitert, ein neuer ist bestellt.
  fehlgeschlagen,

  /// Unterwegs oder gleich unterwegs.
  laeuft,

  /// Alles beim Server.
  gespeichert,
}

/// Der Zustand für die Fußzeile.
///
/// Vorher stand dort bei einem Fehlschlag „Speichere …" — dieselbe Zeile wie
/// bei einem laufenden Speichern. Der Unterschied zwischen „ist gleich da"
/// und „ist nicht angekommen" ist aber genau der, auf den es ankommt.
SpeicherAnzeige speicherAnzeige({
  required bool gueltig,
  required bool laeuftGerade,
  required bool offen,
  required int fehlversuche,
}) {
  if (!gueltig) return SpeicherAnzeige.unvollstaendig;
  if (fehlversuche > 0) return SpeicherAnzeige.fehlgeschlagen;
  if (laeuftGerade || offen) return SpeicherAnzeige.laeuft;
  return SpeicherAnzeige.gespeichert;
}
