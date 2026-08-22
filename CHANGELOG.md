# Änderungen

Patchnotes je Version, jeweils vom vorigen Release bis zur nächsten
Buildnummer. Die Nummer hinter dem `+` teilen sich iOS und Android und zählt
fortlaufend weiter — Play nimmt denselben `versionCode` kein zweites Mal an.

Sortiert nach dem, was sich an der App ändert, nicht nach der Reihenfolge, in
der es entstand. Zwischenstände, die es nie in ein Release geschafft haben,
stehen deshalb nicht drin — wer 1.1.0 benutzt hat, hat sie nie gesehen.

## 1.2.0+4 — 22. August 2026

47 Commits seit 1.1.0+3 (11. August). Der Schwerpunkt liegt auf dem, was man
zuerst sieht: Start, Homescreen, Favoriten.

### Neu

- **Animierter Startbildschirm.** Die grüne Markenhälfte fährt von oben ein,
  die rote von unten, sie treffen sich in der Mitte, dann erscheint die
  Wortmarke. Ein Tipp überspringt. Der Schirm bleibt danach stehen, bis der
  Homescreen wirklich geladen ist, statt nach fester Zeit abzublenden — und
  solange gewartet wird, läuft eine Welle aus drei Punkten in den Markenfarben
  von links nach rechts. Vorher stand ein Standbild, an dem nicht zu erkennen
  war, ob geladen wird oder etwas hängt. Bleiben die Daten aus, blendet er
  nach 8 Sekunden trotzdem ab; ein Logo, aus dem man nicht herauskommt, wäre
  schlimmer.
- **„Meine Vereine" auf dem Homescreen.** Zwischen Ligen und News steht das
  nächste Spiel eines favorisierten Vereins — und alle weiteren an demselben
  Tag, denn an einem Pokal-Samstag will man nicht nur den 13:00-Anstoß sehen.
  Jede Zeile trägt das Wettbewerbslogo: am selben Tag stehen Pokal und Liga
  nebeneinander, und Profis und zweite Mannschaft tragen denselben Kurznamen.
- **Jede Karte sagt selbst, was ansteht.** „9 Tipps offen · bis Fr., 20:30"
  steht auf der Karte, die es betrifft, statt in einem Kasten obendrüber, der
  immer nur für eine Runde sprach. Fristen stehen absolut, nicht als
  Countdown — eine Restdauer veraltet auf einer Karte, die minutenlang
  unverändert dasteht. Läuft ein Draft, gewinnt der: seine Uhr tickt in
  Minuten, und die Karte sagt dann auch, ob **du** dran bist.
- **Die Ligakarte zeigt den Tabellenplatz.** „Platz 3 / von 10", Rang 1 in
  Gold. „Kader steht" ist eine Auskunft für genau eine Woche im Jahr; sobald
  die Saison läuft, will man den Platz sehen. Vor dem ersten gewerteten
  Spieltag bleibt es beim Zustandswort — dort stünden sonst alle auf 1, und
  das wäre eine Reihenfolge nach Zufall.
- **„Ligen entdecken" hat einen Knopf „Mit Einladungscode beitreten".** Der
  Schirm listet nur öffentliche Ligen; eine private taucht in keinem
  Suchergebnis auf, egal wie genau man ihren Namen tippt. Wer eingeladen
  wurde, suchte dort vergeblich. Beide Leerzustände nennen den Code jetzt als
  Weg, statt nur „keine Treffer" zu melden.
- **Vereinswappen beim Tippen.** Die Spielzeilen zeigten nur Namen; jetzt
  steht links und rechts das Wappen — dasselbe Zeichen, das Tabelle, Spielplan
  und Torjägerliste schon benutzen.
- **Datenschutzerklärung im Menü**, direkt über dem Impressum.

### Geändert

- **Der Homescreen ist neu aufgeteilt.** Vorher dreimal derselbe Anblick: drei
  gleich aussehende Listen in gleichen Kästen unter gleichen Überschriften.
  Jetzt hat jeder Bereich seine eigene Form — Fantasy sind quer wischbare
  Karten, Tippspiel schlanke Karten, News eine Querleiste. Die Kartenbreite
  ist so gerechnet, dass **genau vier Ligen** ohne Wischen dastehen; ab der
  fünften wird gescrollt. Der Abschnitt mit Inhalt steht oben: Wer nur ein
  Tippspiel hat, sieht nicht mehr zuerst eine leere Ligareihe. Die
  Begrüßungskarte ist zu einer schlanken Zeile geworden, News zeigt drei
  Schlagzeilen statt fünf.
- **Liga- und Tippspiel-Karten tragen den Zustand auf einem Sockel.** Fläche,
  Farbe, Verlauf, Rahmen und Maße bleiben; neu ist die Aufteilung darin. Der
  Zustand sitzt unten in einer abgesetzten Leiste statt hinter einer dünnen
  Trennlinie, der Name führt deutlich vor dem Untertitel, und der freie Platz
  liegt über dem Namen statt unter ihm. Vorher konkurrierten zwei gleich fette
  Zeilen auf einer 88 Punkt breiten Karte.
- **Farben nach Modus, kräftiger als vorher.** Redraft grün, Dynasty rot — die
  beiden Markenfarben statt einer gewürfelten Farbe je Liga, die den
  Homescreen bunt aussehen ließ. Gemischt wird gegen den fast schwarzen
  Seitengrund statt gegen die graue Kartenfläche: Grau frisst die Sättigung,
  dieselbe Markenfarbe sah darüber aus wie stumpfes Salbeigrün. Wer zwei Ligen
  desselben Modus unterscheiden will, gibt einer ein Logo — dessen Farbe
  sticht die Modusfarbe.
- **Die „+"-Karte am Ende der Kartenreihen ist raus.** Sie stand die ganze
  Saison für etwas, das man ein- oder zweimal im Jahr tut — und war bei vier
  Ligen ausgerechnet die angeschnittene fünfte Karte am rechten Rand, also
  genau dort, wo man eine weitere Liga vermutet und wischt. Angelegt und
  beigetreten wird über das „+" oben rechts.
- **Der „+"-Schirm sagt jetzt, was der Unterschied ist.** Vorher zwei
  bildschirmfüllende Fotos mit je einem Wort darauf — hübsch, aber die eine
  Frage an dieser Stelle blieb offen. Jetzt trägt jede Karte eine Zeile
  („Spieler draften, Kader managen, Woche für Woche punkten" / „Ergebnisse
  tippen, Punkte sammeln, Tabelle klettern"), und der Beitreten-Weg ist eine
  eigene Karte statt eines Anhängsels.
- **Erstellen-Formulare und Tipprunden-Einstellungen sehen endlich gleich
  aus.** Dieselben Abschnitte mit leiser Überschrift, der Hauptknopf fest am
  unteren Rand statt am Ende der Liste — beim Tippspiel liegt dazwischen der
  ganze Wertungs-Editor; wer oben den Namen tippte, sah nicht, dass es
  überhaupt weitergeht.
- **Die Tipprunden-Einstellungen sind gruppiert.** Statt zwölf gleich fetter
  Zeilen mit demselben grünen Symbol jetzt fünf Gruppen: Meine Teilnahme,
  Mitglieder, Regeln & Wertung, Erscheinungsbild — und eine rot abgesetzte
  Gefahrenzone. Vorher stand „Löschen" einen Strich unter „Adminrechte
  übergeben".
- **Wettbewerbe wählt man am Wappen.** „Bundesliga" und „2. Bundesliga"
  unterscheiden sich als Text in zwei Zeichen, als Logo sofort.
- **Sichtbarkeit erklärt sich an der Option selbst**, eine Zeile Begründung je
  Wahlmöglichkeit. Vorher standen dort zwei Wörter, und was „öffentlich"
  bedeutet, stand in einem Hinweis darunter, der sich beim Umschalten änderte
  — man musste erst wählen, um zu erfahren, was man wählt.
- **Der Olivstich ist überall weg.** Materials Auswahlelemente färben sich aus
  einer Farbe, die sich aus dem grünen Seed ableitet; heraus kam ein stumpfes
  Oliv, das zu keiner Fläche der App passte. Betraf Umschalter, Filterpillen
  und das Seitenmenü.
- **Die Favoriten-Zeilen schreiben Vereinsnamen aus.** „ENE", „HAN", „ELV"
  sagen ohne Tabellenkontext wenig; die Anstoßzeit steht jetzt zwischen den
  Mannschaften statt am rechten Rand.
- **Torjäger stehen mit Vereinswappen statt Spielerfoto** — der Datenanbieter
  liefert für die unteren Ligen überwiegend keinen Kopf, sondern seinen
  eigenen Platzhalter, und zwar als Bild-Adresse statt als Leerwert. Die Liste
  zeigte deshalb graue Fremd-Silhouetten.

### Behoben

- **Der Live-Tab zeigte 0:0, bevor angepfiffen war.** Über Spielen, die erst
  in ein paar Minuten anfingen, stand ein Ergebnis; jetzt steht dort bis zum
  Anpfiff die Anstoßzeit. Der Datenfeed führt schon vor dem Anstoß ein 0:0,
  und die App fragte nur, ob Zahlen da sind — nicht, ob das Spiel läuft.
- **Damit wertete die Live-Tabelle Spiele, die noch nicht liefen.** Derselbe
  Fehler entschied mit, welche Spiele in die Live-Wertung einfließen: Wer 0:0
  getippt hatte, führte die Tipprunde an, bevor der Ball rollte. Das war der
  ernstere Teil und ist mit derselben Korrektur weg.
- **Die Torjägerliste zeigte Rote Karten statt Tore.** Der Datenanbieter hat
  zwei Nummernkreise für Ereignistypen, und sie überschneiden sich —
  gefiltert wurde auf die Rote Karte. Aufgefallen ist es nur in der 2. Liga,
  weil dort schon gespielt wird; die Bundesliga-Liste war leer und damit
  unauffällig.
- **Abmelden und neu anmelden führte nicht zurück zum Homescreen.** Wer sich
  aus dem geöffneten Profil abmeldete, blieb im Profil stehen, meldete sich
  über dessen Knopf neu an — und landete wieder dort. Sichtbar wurde die App
  erst nach vollständigem Beenden. Der Fehler saß nicht in der Anmeldung,
  sondern im Navigationsstapel; jetzt wird beim Wechsel des Kontos alles
  darüber weggeräumt, egal wo abgemeldet wurde.
- **Ein gelöschter Tipp blieb überall mitgezählt.** Auf der Karte stand weiter
  „Alles getippt". Die Zahl war nicht falsch gerechnet, sie war alt: Der
  Zwischenspeicher wurde beim normalen Speichern nie aufgefrischt. Betroffen
  waren auch Tipp-Tabelle, Duelle-Tab, Platzierungs-Chip und die
  Profil-Bilanz.
- **Ein Verein ließ sich nicht abwählen.** Zwei Favoriten standen mit Wappen
  da, darunter blieb alles leer, und der Stern half nicht — er traf eine
  andere Zeile als die gespeicherte. Zu manchen Favoriten gab es überhaupt
  keinen Stern, weil die Auswahl nur Vereine des aktuellen Spielplans zeigte.
  Und ein dritter Verein tauchte auf dem Homescreen auf, den nie jemand
  favorisiert hatte: Eine alte Kennung kürzte sich zufällig zu der eines
  fremden Klubs. Altlasten dieser Art sind serverseitig entfernt — wer den
  Verein weiter will, setzt den Stern einmal neu.
- **Der Favoriten-Screen verschwieg den einzigen Favoriten.** Die Wappenleiste
  erschien erst ab zwei; bei genau einem nannte der Screen ihn nirgends und
  behauptete darunter, es sei keiner ausgewählt.
- **Leerzustände zeigen den Weg.** „Kein Spielplan verfügbar." war ein nackter
  Satz — wer dort landete, musste selbst darauf kommen, dass oben rechts ein
  Plus wartet. Alle vier Zustände (kein Favorit, keine Spiele, keine News,
  Laden fehlgeschlagen) führen jetzt zur Auswahl; beim Fehler steht „Erneut
  laden" vorn.
- **Der Lüneburger SK Hansa trug das Wappen von Hansa Rostock.** Kein
  Zuordnungsfehler auf unserer Seite: Beim Datenanbieter liegt unter der ID
  des LSK Hansa Byte für Byte dieselbe Datei wie unter Hansa Rostock. Bis der
  Anbieter das korrigiert, holt die App das richtige Wappen aus einer zweiten
  Quelle.
- Lange Namen wurden auf den Karten falsch gekappt („Xcode Xcode" wurde zu
  „Xcode").
- Der gelbe Doppelstrich unter der Wortmarke im Startbildschirm ist weg. Er
  war kein Designfehler, sondern Flutters eingebauter Hinweis auf ein
  fehlendes `Material` — behoben statt übermalt.
- Der Datenschutz-Link lief ins Leere: Unter der alten Adresse fing ein früher
  registrierter Service Worker der Web-Demo jede Anfrage ab und lieferte den
  zwischengespeicherten App-Rumpf aus.

### Intern

- **Android-Release war bisher nicht auslieferbar.** Drei Lücken des
  Flutter-Templates geschlossen: `INTERNET` stand nur im Debug-Manifest (ein
  Release-Build wäre ohne Fehlermeldung nicht an den Server gekommen —
  dieselbe stumme Falle wie beim ersten TestFlight-Build), signiert wurde mit
  dem Debug-Key (ein so signiertes AAB lehnt Play ab), und `android/build/`
  lief in die Versionsverwaltung.
- Store-Assets für Google Play: Symbol, Feature-Grafiken, Screenshots,
  Werbegrafiken.
- Der native Startbildschirm ist absichtlich leer bis auf die
  Hintergrundfarbe — stünde dort das Logo, sähe man es erst fertig, dann
  verschwinden und in der Animation neu einfliegen.
