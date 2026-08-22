# Änderungen

Patchnotes je Version. Die Build-Nummer hinter dem `+` teilen sich iOS und
Android und zählt fortlaufend weiter — Play nimmt denselben `versionCode` kein
zweites Mal an.

## 1.2.0+4 — 22. August 2026

### Behoben

- **Der Live-Tab zeigte 0:0, bevor angepfiffen war.** Über Spielen, die erst
  in ein paar Minuten anfingen, stand ein Ergebnis; jetzt steht dort bis zum
  Anpfiff die Anstoßzeit. Ursache war nicht die Anzeige: Der Datenfeed führt
  schon vor dem Anstoß ein 0:0, und die App fragte nur, ob Zahlen da sind —
  nicht, ob das Spiel läuft.
- **Damit wertete die Live-Tabelle Spiele, die noch nicht liefen.** Derselbe
  Fehler entschied mit, welche Spiele in die Live-Wertung einfließen: Wer 0:0
  getippt hatte, führte die Tipprunde an, bevor der Ball rollte. Das war der
  ernstere Teil des Fehlers und ist mit derselben Korrektur weg.
- **Der Lüneburger SK Hansa trug das Wappen von Hansa Rostock.** Kein
  Zuordnungsfehler auf unserer Seite — beim Datenanbieter liegt unter der ID
  des LSK Hansa Byte für Byte dieselbe Datei wie unter Hansa Rostock. Bis der
  Anbieter das korrigiert, holt die App das richtige Wappen aus einer zweiten
  Quelle.
- Lange Namen wurden auf den Karten falsch gekappt („Xcode Xcode" wurde zu
  „Xcode").

### Geändert

- **Liga- und Tippspiel-Karten sind neu angeordnet.** Fläche, Farbe, Verlauf,
  Rahmen und Maße bleiben, wie sie waren. Neu ist die Aufteilung darin: Der
  Zustand sitzt unten auf einem abgesetzten Sockel statt hinter einer dünnen
  Trennlinie, der Name führt jetzt deutlich vor dem Untertitel, und der freie
  Platz liegt über dem Namen statt unter ihm. Vorher konkurrierten zwei gleich
  fette Zeilen auf einer 88 Punkt breiten Karte, und der Textblock schwebte mit
  totem Raum darunter.
- **Die „+"-Karte am Ende der Kartenreihen ist raus.** Sie stand die ganze
  Saison für etwas, das man ein- oder zweimal im Jahr tut — und war bei vier
  Ligen ausgerechnet die angeschnittene fünfte Karte am rechten Rand, also
  genau dort, wo man eine weitere Liga vermutet und wischt. Angelegt und
  beigetreten wird weiterhin über das „+" oben rechts. Wer noch keine Liga hat,
  sieht unverändert die erklärende Einstiegszeile.

### Neu

- **„Ligen entdecken" hat einen Knopf „Mit Einladungscode beitreten".** Der
  Schirm listet nur öffentliche Ligen; eine private taucht in keinem
  Suchergebnis auf, egal wie genau man ihren Namen tippt. Wer eingeladen wurde,
  suchte dort deshalb vergeblich und musste zurück auf den Homescreen. Jetzt
  steht die Tür unter dem Suchfeld — und beide Leerzustände nennen den Code als
  Weg, statt nur „keine Treffer" zu melden.
