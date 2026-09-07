import 'dart:async';

/// **Dieselbe Frage wird nicht mehrfach gestellt.**
///
/// Gemeldet: *„Auch bei guter Internetverbindung sind ganz oft Ladescreens."*
/// Nachgemessen war das keine Langsamkeit, sondern eine Menge: Der komplette
/// Bundesliga-Spielplan (137 KB, 306 Partien) wird von **sechs** Stellen
/// unabhängig voneinander geholt, und drei davon holen ihn nur, um eine
/// einzige Zahl daraus zu rechnen:
///
/// | Aufrufer | wofür |
/// |---|---|
/// | `fantasySeasonFixturesProvider` | Fantasy-Spieltag, Sperren, Waiver |
/// | `leagueSeasonFixturesProvider('bundesliga')` | Liga-Übersicht, Live-Tab |
/// | `seasonFixturesProvider` | Tippspiel, gewählter Wettbewerb |
/// | `currentRoundProvider` | **eine Zahl** — der aktuelle Spieltag |
/// | `availableRoundsProvider` | die Liste der Spieltagsnamen |
/// | `roundFixturesProvider(n)` | die Partien **eines** Spieltags |
///
/// Die letzten drei rechnen ihr Ergebnis im Adapter aus der ganzen Saison aus
/// (`getRoundFixtures` ruft `getSeasonFixtures` und filtert) — und weil
/// `sportsProviderFor` bei **jedem** Aufruf ein neues Adapter-Objekt baut,
/// konnte auch keine Instanz sich etwas merken. Ein Spieltagswechsel im
/// Tippspiel lud damit 137 KB nach, um 9 Partien anzuzeigen.
///
/// Riverpod hält jedes Ergebnis für sich fest (kein `autoDispose` in dieser
/// App). Was fehlte, war das Teilen **zwischen** Fragestellern, die dasselbe
/// wissen wollen. Genau das tut dieses Bündel, und mehr nicht:
///
/// * **Läuft die Frage gerade**, bekommt der zweite Frager dieselbe Antwort
///   statt einer zweiten Verbindung. Das ist der eigentliche Gewinn: Beim
///   Öffnen eines Schirms fallen die Fragen im selben Moment an.
/// * **Kurz danach** gilt die Antwort noch (Sekunden, nicht Minuten). Sie
///   deckt den Moment ab, in dem ein Schirm aufgebaut wird — nicht mehr.
/// * **Ein Fehler wird nicht gemerkt.** Der nächste Versuch fragt wirklich.
///
/// Die kurze Geltung ist Absicht: Ein „Zum Neuladen ziehen" muss neu laden,
/// und ein laufendes Spiel muss seinen Stand ändern dürfen. Wer ausdrücklich
/// frisch fragen will, ruft vorher [leeren].
class AbfrageBuendel {
  final _laufend = <String, Future<Object?>>{};
  final _fertig = <String, ({Object? wert, DateTime zeit})>{};

  /// Für Tests: die Uhr stellbar machen. Eine Geltungsdauer, die an
  /// `DateTime.now()` hängt, ist sonst nicht prüfbar.
  DateTime Function() jetzt = DateTime.now;

  Future<T> hole<T>(
    String schluessel,
    Duration gilt,
    Future<T> Function() abruf,
  ) {
    final da = _fertig[schluessel];
    if (da != null && jetzt().difference(da.zeit) < gilt) {
      return Future<T>.value(da.wert as T);
    }
    final laeuft = _laufend[schluessel];
    if (laeuft != null) return laeuft.then((w) => w as T);

    final future = abruf().then((wert) {
      _fertig[schluessel] = (wert: wert, zeit: jetzt());
      return wert;
    }).whenComplete(() {
      // **Klammern, kein Pfeil.** `Map.remove` liefert den gespeicherten Wert
      // zurück — und der ist hier selbst ein `Future`. Ein `whenComplete`,
      // dessen Rückruf ein Future zurückgibt, wartet darauf: Die Abfrage
      // wartete damit auf sich selbst und wurde nie fertig.
      _laufend.remove(schluessel);
    });
    _laufend[schluessel] = future;
    // **Ein Fehler braucht immer einen Zuhörer.** Die Frager bekommen ihn
    // über ihre eigenen Futures; ohne diesen stillen Mithörer fiele er, wenn
    // gerade keiner wartet, als unbehandelt in die Zone — und das reißt im
    // Debug-Build die App hoch, für einen Netzfehler, den längst jemand
    // anzeigt.
    unawaited(future.then((_) {}, onError: (_) {}));
    return future;
  }

  /// Vergisst gemerkte Antworten — alle, oder die mit diesem Präfix.
  /// Laufende Fragen bleiben unangetastet: Sie abzubrechen hieße, den
  /// Wartenden eine Antwort wegzunehmen, die gleich da ist.
  void leeren([String? praefix]) {
    if (praefix == null) {
      _fertig.clear();
      return;
    }
    _fertig.removeWhere((k, _) => k.startsWith(praefix));
  }

  /// Nur für Tests: wie viele Antworten liegen bereit?
  int get gemerkt => _fertig.length;
}
