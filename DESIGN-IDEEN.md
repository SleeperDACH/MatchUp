# Design-Ideen: moderner und cleaner

Stand 15.10.2026. Sortiert nach Wirkung. **Alle acht Punkte sind umgesetzt**
(siehe CLAUDE.md, „Cleaner: Kästen, Schrift, Farbe, Text, Navigation"). Beruht auf den zuletzt bearbeiteten
Schirmen (Übersicht, MatchUp-Tab, Kader, Profil, Tabelle), noch nicht auf einer
Durchsicht der ganzen App.

## 1. Weniger Kästen, mehr Luft

Fast alles steckt heute in einer Karte mit Rand, oft Karte in Karte. Clean
wirkt eine App vor allem über Abstand.

- Karten nur noch für Dinge, die man antippt (ein Duell, ein Spieler).
- Abschnitte wie „Ergebnisse“ oder „Spielplan“ trennt eine kleine
  Versalien-Überschrift plus Weißraum, kein Rahmen.

Größter Effekt von allen Punkten.

## 2. Schrift-Hierarchie mit vier Stufen

Inter ist die Grundlage. In `Schrift` gibt es aber viele Größen (h1, titel,
koerperKlein, klein, winzig …), die gemischt werden. Künftig vier Stufen:

1. große Zahl
2. Titel
3. Text
4. kleines Label in Versalien

Punkte haben immer die Hauptrolle: groß, fett, feste Ziffernbreiten. Alles
andere tritt leise dahinter zurück.

## 3. Farbe nur mit Bedeutung

- **Grün** heißt „ich, gut“.
- **Rot** heißt „live, schlecht“.
- **Alles andere ist Grau.**

Positionsfarben, Chancenfarben und farbige Symbolkreise sammeln sich gerade an.
Positionsfarben auf einen kleinen Punkt oder Strich reduzieren statt ganzer
Flächen.

## 4. Weniger erklärender Text in der Oberfläche

Hinweise wie „beruht auf 9 von 11“, „spielfrei“ und Statuszeilen sind korrekt,
aber zahlreich. Nur die Zahl zeigen, den Rest per Tipp oder Info-Symbol.
Sleeper wirkt so ruhig, weil fast nichts erklärt wird.

## 5. Navigation entschlacken

Heute drei Ebenen: Bottom-Navigation, Seitenmenü, Liga-Reiter.

- Seitenmenü auflösen, Inhalte ins Profil oder in die Bottom-Navigation.
- Die nicht mehr erreichbare MatchUp-Detailseite
  (`matchup_detail_screen.dart`) entfernen.

## 6. Bewegung statt Statik

Macht die App modern, ohne Platz zu kosten:

- Live-Punkte zählen hoch, statt zu springen.
- Kurzes Aufleuchten bei einem Tor.
- Haptik beim Aufstellen.
- Weiche Übergänge zwischen den Wochen.

## 7. Skelette statt Spinner

Beim Laden die Form der Seite grau andeuten, statt einen Kreis drehen zu
lassen. Die Seite wirkt schneller und springt nicht.

## 8. Ein einheitlicher Symbolsatz

Gleiche Strichstärke, und Symbole nur dort, wo sie schneller sind als ein
Wort. Bei den Liga-Reitern ist das schon umgesetzt.

## Empfohlener Einstieg

Mit **1** und **2** auf der **Liga-Übersicht** und im **Kader** anfangen. Das
sind die meistgesehenen Schirme, dort sieht man den Unterschied sofort.

Zuerst für beide eine Vorher-nachher-Vorschau als Golden-Bild bauen, dann
entscheiden, bevor die ganze App umgestellt wird.
