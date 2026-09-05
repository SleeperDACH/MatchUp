import 'dart:async';

/// **Ein Live-Strom, der nicht an seiner Verbindung hängt.**
///
/// Gemeldet: *„In der App habe ich öfter den Fehler ‚Deine Ligen ließen sich
/// nicht laden‘ — RealtimeSubscribeException, Status timedOut."*
///
/// Supabase' `.stream()` tut **zwei** Dinge in einem: Es holt einen ersten
/// Schnappschuss und abonniert die Änderungen. Scheitert das Abonnement — ein
/// Funkloch beim Start, ein langsamer Kaltstart, ein WLAN-Wechsel —, wirft der
/// ganze Strom, und die Liste kommt **gar nicht**. Dabei wäre sie über eine
/// gewöhnliche Abfrage längst da: Der Fehler betrifft das Zuhören, nicht das
/// Lesen.
///
/// Diese Hülle trennt beides:
///
/// * **Der Schnappschuss kommt zuerst**, über [abfrage]. Die Liste steht
///   damit, bevor die Verbindung überhaupt eine Rolle spielt.
/// * **Das Abonnement kommt danach** und liefert nur noch Aktualisierungen.
/// * **Ein Verbindungsfehler wird nicht durchgereicht**, solange schon Daten
///   geflossen sind. Er löst einen neuen Versuch mit wachsendem Abstand aus —
///   der Nutzer sieht den letzten Stand, nicht eine Fehlerkarte.
/// * **Erst wenn auch die Abfrage scheitert**, gibt es einen Fehler. Dann ist
///   wirklich nichts zu zeigen, und das darf man sagen.
///
/// Die Regel dahinter ist dieselbe wie im MatchUp-Tab: *Ein Fehler ersetzt den
/// Inhalt nur, wenn es keinen gibt.* Hier steht sie eine Schicht tiefer,
/// damit nicht jeder Schirm sie einzeln erfinden muss.
Stream<T> liveMitRueckfall<T>({
  required Future<T> Function() abfrage,
  required Stream<T> Function() strom,
  Duration ersterAbstand = const Duration(seconds: 2),
  Duration groessterAbstand = const Duration(seconds: 30),
  void Function(Object fehler)? beiFehler,
}) {
  late final StreamController<T> steuerung;
  StreamSubscription<T>? abo;
  Timer? wiederversuch;
  var abstand = ersterAbstand;
  var hatDaten = false;
  var beendet = false;

  Future<void> schnappschuss() async {
    try {
      final daten = await abfrage();
      if (beendet || steuerung.isClosed) return;
      hatDaten = true;
      steuerung.add(daten);
    } catch (e) {
      beiFehler?.call(e);
      // **Nur melden, wenn nichts dasteht.** Ein fehlgeschlagener
      // Nachladeversuch über vorhandenen Daten ist kein Grund, sie wegzuwerfen.
      if (!hatDaten && !beendet && !steuerung.isClosed) steuerung.addError(e);
    }
  }

  void verbinden() {
    abo?.cancel();
    abo = strom().listen(
      (daten) {
        abstand = ersterAbstand; // Verbindung steht wieder.
        hatDaten = true;
        if (!steuerung.isClosed) steuerung.add(daten);
      },
      onError: (Object e) {
        beiFehler?.call(e);
        abo?.cancel();
        abo = null;
        // Ohne Daten hilft nur die Abfrage — sie geht über HTTP und ist von
        // der Realtime-Verbindung unabhängig.
        if (!hatDaten) schnappschuss();
        if (beendet) return;
        wiederversuch?.cancel();
        wiederversuch = Timer(abstand, () {
          final naechster = abstand * 2;
          abstand = naechster > groessterAbstand ? groessterAbstand : naechster;
          if (!beendet) verbinden();
        });
      },
    );
  }

  steuerung = StreamController<T>(
    onListen: () {
      schnappschuss();
      verbinden();
    },
    onCancel: () {
      beendet = true;
      wiederversuch?.cancel();
      abo?.cancel();
    },
  );
  return steuerung.stream;
}
