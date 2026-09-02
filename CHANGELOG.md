# Änderungen

Patchnotes je Version, jeweils vom vorigen Release bis zur nächsten
Buildnummer. Die Nummer hinter dem `+` teilen sich iOS und Android und zählt
fortlaufend weiter — Play nimmt denselben `versionCode` kein zweites Mal an.

Sortiert nach dem, was sich an der App ändert, nicht nach der Reihenfolge, in
der es entstand. Zwischenstände, die es nie in ein Release geschafft haben,
stehen deshalb nicht drin — wer 1.1.0 benutzt hat, hat sie nie gesehen.

## 1.4.0+6 — 31. August 2026

89 Commits seit 1.3.0+5 (26. August) — der erste Build **während** einer
laufenden Saison, und das merkt man ihm an: Vieles davon sind Dinge, die erst
auffielen, als der 1. Spieltag wirklich gespielt wurde.

### Neu

- **Transfers.** Ein eigener Bereich in der Liga-Übersicht und im Kader-Tab:
  auf der einen Seite deine offenen Vorgänge (eingehende Trade-Angebote,
  eigene Waiver-Anträge), auf der anderen die Kaderbewegungen der ganzen Liga.
  Zu- und Abgang stehen als **ein** Vorgang nebeneinander — wer jemanden
  geholt hat, hat meist im selben Zug jemanden abgegeben, und das gehört
  zusammen. Ein Trade steht als eine Box mit beiden Seiten.
- **Die voraussichtliche Aufstellung im Spielerprofil.** Als Formation
  aufgestellt, nicht als Liste, und sie wechselt nach dem letzten Abpfiff auf
  den nächsten Spieltag. Wer nicht in der Elf steht, sieht das sofort.
- **Verletzungen und Sperren.** Ein Symbol an der Spielerkarte, der genaue
  Grund im Profil — in der Free Agency steht er direkt in der Zeile. Einen
  verletzten Spieler zu holen ist der teuerste Fehler dort.
- **Kader-Limits je Position**, einstellbar in den Einstellungen und schon
  beim Erstellen einer Liga. Sie gelten je Position einzeln.
- **Der Waiver hat eine Frist: Montag 15:00.** Ab dem Anpfiff seines Vereins
  liegt ein Spieler auf dem Waiver; montags um 15 Uhr werden alle Anträge nach
  Priorität vergeben. Bei englischen Wochen (Spiele Dienstag *und* Mittwoch)
  Donnerstag 15 Uhr. Dazwischen gilt wieder „first come, first served".
  Gedroppte Spieler außerhalb der Frist liegen 24 Stunden auf dem Waiver.
- **Die Elf der Vorwoche wird übernommen.** Wer nichts tut, startet nicht mehr
  leer in den Spieltag — die letzte gestellte Aufstellung rückt nach, gefiltert
  auf den aktuellen Kader. Vor dem Einbau hatten elf von zwölf Managern für den
  zweiten Spieltag noch gar nichts stehen.
- **Die Free Agency zeigt jetzt alle Spieler**, auch die in fremden Kadern:
  oben die freien, darunter die vergebenen mit dem Team des Besitzers und einem
  Trade-Knopf. Sortiert nach den Punkten der laufenden Saison, die auch in der
  Zeile stehen. Die separate Spielersuche entfällt damit.
- **Eine neue Formation: 4-2-4** — von acht auf neun. (Kurz waren es elf,
  3-3-4 und 3-6-1 sind auf Wunsch wieder raus.) Wie viele davon *du* stellen
  kannst, hängt an deinem Kader: Formationen, für die dir Spieler fehlen,
  stehen gedämpft da und sagen beim Antippen, was fehlt.
- **Das Draft-Board bleibt nach dem Draft erreichbar** — wer nachsehen will,
  wer wen wann gezogen hat, kommt wieder hin.

### Wertung

- **Tore zählen 15 statt 16, Vorlagen 10.** Stürmer waren zu stark.
- **Das Mittelfeld bekommt 4 Punkte für die Null hinten**, und die
  Pass-Schwellen liegen niedriger (30 und 45). Nach Spieltag 1 gemessen liegen
  Abwehr, Mittelfeld und Sturm damit bei 13,7 / 15,0 / 14,4 — vorher war das
  Mittelfeld das Schlusslicht.
- **Torhüter bekommen keinen Einsatzbonus mehr.** Alle achtzehn spielten 90
  Minuten; der Sockel war für sie eine Konstante, die kein Spiel vom anderen
  unterschied, und hob ihren Schnitt auf 27,7. Jetzt 17,7. Schlechte
  Torwart-Tage können damit ins Minus gehen.
- **Genaue Pässe werden bepunktet**, und „abgefangene Bälle" hießen bisher
  fälschlich „Balleroberung" — zwei verschiedene Werte, jetzt beide richtig.
- **Torhüter bekamen ihre Gegentore doppelt gezählt.** Behoben, samt einer
  Nachlese, die Stats nach dem Abpfiff automatisch korrigiert, wenn die Quelle
  nachliefert.

### Behoben

- **Das Karussell im MatchUp-Tab bleibt stehen, wo man ist** — beim
  Runterscrollen, beim Nachladen und beim Wechsel in einen anderen Reiter. Drei
  verschiedene Ursachen, alle drei weg.
- **Die Aufstellung verlor Änderungen** auf vier Wegen (unter anderem beim
  schnellen Zurücktippen und beim Verlassen des Schirms). Alle vier geschlossen.
- **Live-Punkte kamen nicht überall an.** Die Kette vom Sync bis zur Anzeige
  hing an drei Stellen; alle drei angeschlossen.
- **Der Auto-Pick stolperte über die eigene Wertung** und zog gelegentlich
  Unsinn.
- **Eigentore fehlten im Spielverlauf.** Sie sind jetzt drin und als solche
  gekennzeichnet: roter Ball, kein Vorlagengeber, Hinweis „Eigentor".
- **Ein Waiver-Antrag ließ sich für sieben Vereine nicht abschicken** — der
  Spielplan und die Kader schreiben dieselben Vereine verschieden („1. FSV
  Mainz 05" gegen „FSV Mainz 05").
- **Ein 1:1-Tausch scheiterte am Kaderlimit**, obwohl er die Zahl nicht ändert.
- **Konten ohne Profil heilen sich beim nächsten Anmelden.** Wer davon
  betroffen war, stand in Ligen und Chats namenlos da.
- **Beitritte und Draft-Start kommen ohne App-Neustart an.**
- **Ein abgegebener Spieler verschwindet aus der Elf**, statt als Karteileiche
  stehen zu bleiben.
- Punktzahlen mit zwanzig Nachkommastellen (`221.10000000000002`) gibt es
  nirgends mehr.

### Aussehen

Ein Durchgang durch die ganze App, mit drei Regeln, die ab jetzt überall gelten:

- **Eine Kante für alle Karten.** Kein bunter Rand als Schmuck; Tiefe entsteht
  auf dunklem Grund über die Fläche. Farbe trägt eine Karte nur als leiser
  Schimmer aus der Ecke — und nur, wo etwas ansteht.
- **Eine Schriftleiter für die ganze App.** Vorher standen 224 hartkodierte
  Größen in über zwanzig Abstufungen im Code, darunter Halbschritte.
- **Keine grün gestochenen Flächen mehr.** Das Grün steckte in jeder grauen
  Fläche der App und war nirgends beabsichtigt.

Sichtbar wird das unter anderem hier:

- **Punktstände sind lesbarer**: Die Zehntelstelle steht kleiner und leiser
  hinter der Zahl (**128**,4 statt 128,4), und alle Ziffern sind gleich breit,
  damit in einem laufenden Spiel nichts hin und her wandert.
- **Die Reiterleiste der Liga** trägt Symbol *und* Wort bei allen vieren —
  vorher stand an zweiter Stelle ein Logo ohne Beschriftung.
- **Die Liga-Übersicht** führt mit dem Duell, die Zeilen darunter sagen, was
  ansteht („Noch nicht gestellt", „2 Wechsel in der Liga").
- **Der Favoriten-Tab hat einen Kopf**, das Seitenmenü trägt Inhalt statt drei
  Links, und die Spiele im Live-Tab sind größer.
- **Das Tippspiel spricht dieselbe Sprache**: Karten mit einer Haarlinie statt
  Material-Kästen, Tagesüberschriften als Kapitelmarken, und **Spiele mit
  demselben Anpfiff stehen zusammen** — bei fünf Samstagsspielen stand vorher
  fünfmal „15:30" untereinander.
- **Die Tipp-Tabelle glüht nicht mehr.** Vorher trug jeder Punktgewinn
  Markengrün; jetzt nur noch der Volltreffer. Namen brechen nicht mehr ab.

### Kleinkram

- **Kaderbewegungen und Trades stehen nicht mehr im Liga-Chat** — dafür gibt
  es den Transfers-Bereich. 103 automatische Meldungen sind aus dem Verlauf
  genommen; die Gespräche gingen zwischen ihnen unter.
- **Das ligainterne Tippspiel lässt sich wieder ausschalten**, und beide
  Richtungen fragen vorher nach. Vorher schaltete ein Fingertipp sofort ein —
  und die Zeile verschwand danach.
- **Der Aufstellungs-Schirm springt auf den nächsten Spieltag, sobald der
  laufende abgepfiffen ist.** Vorher gab es ein Fenster, in dem man Spieler
  holen, sie aber nirgends hinstellen konnte.
- **Ein Tipp auf den Namen öffnet überall das Spielerprofil**, auch in der Free
  Agency.
- **Jeder Verein hat eine sichtbare Farbe** — bei Dortmund fehlte sie ganz.

## 1.3.0+5 — 26. August 2026

20 Commits seit 1.2.0+4 (22. August). Zwei Schirme sind neu gebaut — der
Startbildschirm bekommt einen Kopf, der Live-Tab wird eine Tafel — und das
Anmelden geht jetzt auch mit Google und Apple.

### Neu

- **Anmeldung mit Google und Apple.** Auf iOS beide nativ (das System zeigt
  seinen eigenen Dialog), auf Android Google nativ und Apple über den
  Browser, im Web beide über den Browser. Wer sich so anmeldet, bekommt
  automatisch ein Profil mit abgeleitetem Namen — sonst stünde man in jeder
  Liga, Tabelle und jedem Chat namenlos da. Der Name ist ein Vorschlag und
  bleibt änderbar. Ein Abbruch ist kein Fehler und zeigt nichts Rotes an.
- **Der Startbildschirm hat einen Kopf: das nächste Spiel deines Vereins.**
  Die Anstoßzeit steht als große Zahl zwischen beiden Wappen, dahinter
  schimmern die Trikotfarben der beiden Vereine — Rot links heißt Bayern, und
  das sieht man, bevor man den Namen gelesen hat. Läuft das Spiel, steht dort
  das Ergebnis; heute anstehende Spiele tragen „HEUTE" in Gold, laufende
  „LIVE" in Rot. Gezeigt wird das Spiel deines **obersten** Favoriten, nicht
  das früheste des Tages: Wer Bayern über Bochum stellt, will an einem Samstag
  mit beiden Bayern oben sehen. Die übrigen Partien desselben Tages stehen
  weiter unter „Meine Vereine".
- **Der Live-Tab ist neu gebaut.** Statt einer Karte je Wettbewerb eine
  durchgehende Tafel: schmale Kopfzeile je Liga, Spiele als Zeilen darunter,
  Namen zur Mitte hin. Oben steht jetzt der gewählte Tag und, wenn etwas
  läuft, wie viele Spiele. **Die Tagesleiste zeigt, wo etwas los ist** — jeder
  Tag mit Spielen hat einen Punkt, rot, wenn dort gerade gespielt wird, und
  Tage ohne Spiele stehen gedimmt. Vorher waren es fünfzehn gleiche Zellen,
  durch die man sich tippen musste.
- **Die Wettbewerbe stehen als fünf Kacheln am unteren Rand** — Wappen,
  Kurzname, alle ohne Wischen sichtbar und direkt antippbar. Vorher fünf
  farbige Textknöpfe in zwei Reihen, die dauerhaft ein Fünftel des Schirms
  belegten.

### Geändert

- **Der Startbildschirm ist ruhiger geworden.** Die Begrüßung war die größte
  und fetteste Schrift der Seite — sie ist eine graue Zeile über der neuen
  Kopfkarte. Die Ligakarten tragen ihre Farbe nur noch als Hauch in der Ecke
  statt als volle Fläche, und die vierte Karte wird am Rand angeschnitten,
  damit man sieht, dass es seitlich weitergeht. Jeder Abschnittskopf hat einen
  schmalen Strich in der Farbe seines Bereichs — vorher standen dort fünf
  gleiche graue Zeilen ohne Takt.
- **Die Karten sagen nicht mehr, was ansteht.** Die Zustandsleiste am unteren
  Rand („Offen", „Draft läuft", „18 Tipps offen") ist auf Wunsch entfernt;
  die Karten sind dadurch deutlich flacher.
- **Die Teilnehmerzahl einer Fantasy-Liga lässt sich wieder ändern** —
  Zahnrad › Regeln & Format › Teilnehmerzahl. Die Seite dafür gab es, sie war
  nur von nirgendwo zu erreichen. Unter die Zahl der bereits beigetretenen
  Teams lässt sie sich nicht setzen.
- **Vorlesehilfen.** 24 Symbolknöpfe hatten keinen Namen und hießen für
  VoiceOver und TalkBack schlicht „Schaltfläche" — auch das Hamburger-Symbol,
  der Favoriten-Stern und das „+" oben rechts. Blätter-Pfeile nennen jetzt ihr
  Ziel („Weiter zu Spieltag 8") statt ihrer Richtung, und bei +/−-Steppern
  trägt die Beschriftung den Wert mit („Exakt getippt: 3").
- **Große Systemschrift.** Bei 1,3-facher Schrift lief der Liganame unten aus
  der Karte. Die Kartenreihen deckeln die Schrift jetzt und wachsen innerhalb
  dessen in der Höhe mit; alles, was längs steht, wächst weiter ungebremst.

### Behoben

- **Die Fantasy-Kader waren monatelang veraltet:** Zugänge fehlten, längst
  abgewanderte Spieler standen weiter im Pool. Der automatische Kader-Abgleich
  war zwar gebaut, aber nie in Betrieb genommen. Jetzt läuft er täglich — beim
  ersten Lauf kamen 68 Spieler dazu und 62 Abgänge raus. Wer gedraftet oder im
  Kader ist, wird dabei nie entfernt.
- **„Tipptest" war als „Tinntest" zu lesen.** Auf zu knappen Karten schnitt
  Flutter die Unterlängen ab — betroffen war jeder Name mit p, g, j, q oder y.
  Ohne Fehlermeldung, weil formal alles passte.
- **Der eigene Tipp auf der Kopfkarte zeigte nur einen von mehreren.** Wer
  dasselbe Spiel in zwei Runden verschieden getippt hatte, sah trotzdem nur
  eine Zahl. (Die Anzeige ist inzwischen ganz von der Kopfkarte gewichen, s. o.)

### Intern

- **Zwei Schirme lassen sich jetzt ansehen, ohne auf den eigenen Account
  angewiesen zu sein.** Homescreen und Live-Tab haben Golden-Vorschauen mit
  gesetzten Zuständen. Der Anlass war handfest: Bei der Abnahme fehlte dem
  Testaccount eine eigenständige Tipprunde, und der Live-Tab zeigte an einem
  spielfreien Mittwoch nur „Keine Spiele an diesem Tag".
- Ein Test misst, dass Kartennamen mindestens eine volle Zeile hoch sind — den
  „Tinntest"-Fehler hätte ein Bild nicht gefangen, er sah ja aus wie ein Wort.
- Die Reihenfolge der Favoriten lag doppelt vor (Favoriten-Tab und
  Homescreen); sie ist zu einer Regel zusammengezogen.
- Design-Canvas für beide Überarbeitungen unter `design/` — Diagnose des
  Ist-Zustands und die verworfenen Richtungen.

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
