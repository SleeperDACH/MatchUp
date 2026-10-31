import 'erklaerungen.dart';

/// **Glossar** (29.10.2026, Punkt 7 der Nutzer-Analyse: „viel Fachsprache,
/// oft auf Englisch — für die Kicktipp-Runde aus dem Büro nicht normal").
///
/// Jeder Begriff, der in der App steht und nicht selbsterklärend ist, mit
/// höchstens zwei, drei Sätzen. Wo es schon eine Erklärung hinter einem
/// Fragezeichen gibt (`erklaerungen.dart`), steht hier **dieselbe** — ein
/// Begriff, eine Erklärung.
///
/// **Keine Zahlen, die eine Liga selbst einstellt** (Kadergröße, Zeit je
/// Pick, Tipp-Punkte): Sie stimmen sonst für die halbe App nicht.
enum GlossarBereich {
  fantasy('Fantasy'),
  tippspiel('Tippspiel'),
  allgemein('Allgemein');

  const GlossarBereich(this.titel);
  final String titel;
}

typedef GlossarEintrag = ({GlossarBereich bereich, Erklaerung e});

const List<GlossarEintrag> glossar = [
  // ── Fantasy ──────────────────────────────────────────────────────────
  (bereich: GlossarBereich.fantasy, e: erklaerungFantasy),
  (bereich: GlossarBereich.fantasy, e: erklaerungDraft),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Snake-Draft',
      text:
          'Die Reihenfolge dreht sich jede Runde um: Wer in Runde 1 als '
          'Letzter wählt, wählt in Runde 2 als Erster. So gleicht sich ein '
          'später erster Pick wieder aus.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Pick',
      text: 'Ein Zug im Draft. „2.07“ heißt: Runde 2, siebte Wahl.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Auto-Pick',
      text:
          'Läuft deine Zeit im Draft ab, wählt die App für dich — zuerst '
          'aus deiner Wunschliste, sonst den besten freien Spieler.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Wunschliste',
      text:
          'Spieler, die du im Draft haben willst, in deiner Reihenfolge. '
          'Der Auto-Pick nimmt von dort zuerst.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Kader, Startelf und Bank',
      text:
          'Der Kader sind alle deine Spieler. Elf davon stellst du je '
          'Spieltag auf — nur sie sammeln Punkte. Wer auf der Bank sitzt, '
          'punktet nicht.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Formation',
      text:
          'Wie sich deine Elf aufteilt, etwa 4-4-2: vier Abwehr, vier '
          'Mittelfeld, zwei Sturm. Welche Formationen gehen, legt die Liga '
          'fest.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Aufstellung gesperrt',
      text:
          'Sobald der Verein eines Spielers anpfeift, ist er für diesen '
          'Spieltag fest — du kannst ihn weder aus der Elf nehmen noch '
          'hineinsetzen. Alle anderen kannst du weiter tauschen.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'MatchUp',
      text:
          'Dein Duell am Spieltag: Deine Elf gegen die eines anderen Teams '
          'deiner Liga. Wer mehr Punkte holt, gewinnt — das zählt für die '
          'Tabelle.',
    ),
  ),
  (bereich: GlossarBereich.fantasy, e: erklaerungUnentschieden),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Prognose und Siegchance',
      text:
          'Wie viele Punkte deine Elf erwartbar holt, gerechnet aus den '
          'Schnitten deiner Spieler. Während des Spieltags wird daraus eine '
          'Hochrechnung mit den echten Punkten.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Schnitt (Ø)',
      text:
          'Punkte je Einsatz. Spieltage, an denen ein Spieler nicht auf '
          'dem Platz stand, zählen nicht mit.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Free Agent',
      text:
          'Ein Spieler, der keinem Team gehört. Du kannst ihn direkt '
          'holen; ist dein Kader voll, gibst du dafür einen ab.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Droppen',
      text:
          'Einen Spieler aus deinem Kader abgeben. Er ist danach frei, '
          'liegt aber zuerst auf dem Waiver.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Waiver',
      text:
          'Gerade abgegebene Spieler und solche, deren Verein schon '
          'angepfiffen hat, kann man nicht sofort holen, nur beantragen. '
          'Montag um 15 Uhr (in englischen Wochen Donnerstag) werden die '
          'Anträge vergeben.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Waiver-Priorität',
      text:
          'Wollen mehrere denselben Spieler, bekommt ihn, wer in der '
          'Reihenfolge vorne steht. Wer einen Antrag gewinnt, rückt nach '
          'hinten.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Trade',
      text:
          'Ein Tausch mit einem anderen Team: Spieler gegen Spieler, in '
          'manchen Ligen auch Picks. Läuft gerade ein Spieltag, wechseln die '
          'Spieler erst danach.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Transfers',
      text:
          'Die Liste aller Kaderbewegungen deiner Liga — wer wen geholt, '
          'abgegeben oder getauscht hat.',
    ),
  ),
  (
    bereich: GlossarBereich.fantasy,
    e: (
      titel: 'Leaders',
      text:
          'Alle Spieler der Bundesliga nach Punkten in dieser Saison, egal '
          'wem sie gehören.',
    ),
  ),
  (bereich: GlossarBereich.fantasy, e: erklaerungPlayoffs),
  (bereich: GlossarBereich.fantasy, e: erklaerungWinterpause),
  (bereich: GlossarBereich.fantasy, e: erklaerungKaderLimits),
  (bereich: GlossarBereich.fantasy, e: erklaerungVereinsLimit),

  // ── Tippspiel ────────────────────────────────────────────────────────
  (bereich: GlossarBereich.tippspiel, e: erklaerungTippspiel),
  (bereich: GlossarBereich.tippspiel, e: erklaerungGlobal),
  (bereich: GlossarBereich.tippspiel, e: erklaerungLigaTippspiel),
  (
    bereich: GlossarBereich.tippspiel,
    e: (
      titel: 'Exakt, Tordifferenz, Tendenz',
      text:
          'Exakt: das genaue Ergebnis. Tordifferenz: die richtige '
          'Differenz (2:1 getippt, 3:2 gespielt). Tendenz: nur der richtige '
          'Sieger oder das Unentschieden.',
    ),
  ),
  (
    bereich: GlossarBereich.tippspiel,
    e: (
      titel: 'Quoten-Bonus',
      text:
          'Extrapunkte, wenn du einen Außenseiter richtig tippst. '
          'Maßgeblich ist die Wettquote beim Anpfiff.',
    ),
  ),
  (
    bereich: GlossarBereich.tippspiel,
    e: (
      titel: 'Bonustipps',
      text:
          'Tipps auf die ganze Saison, etwa Meister und Absteiger. '
          'Gewertet wird am Saisonende.',
    ),
  ),
  (
    bereich: GlossarBereich.tippspiel,
    e: (
      titel: 'Form',
      text:
          'Die letzten fünf Spiele eines Vereins vor dem getippten Spiel: '
          'S Sieg, U Unentschieden, N Niederlage — das älteste links.',
    ),
  ),

  // ── Allgemein ────────────────────────────────────────────────────────
  (
    bereich: GlossarBereich.allgemein,
    e: (
      titel: 'Englische Woche',
      text:
          'Spiele unter der Woche zwischen zwei Wochenenden, etwa Pokal '
          'oder Europapokal.',
    ),
  ),
  (
    bereich: GlossarBereich.allgemein,
    e: (
      titel: 'Favoriten',
      text:
          'Deine Lieblingsvereine. Ihr nächstes Spiel steht oben auf dem '
          'Startbildschirm, und auf Wunsch meldet die App Tore und Anpfiff.',
    ),
  ),
  (bereich: GlossarBereich.allgemein, e: erklaerungSichtbarkeit),
];

/// Sortierschlüssel nach deutschem Alphabet: Umlaute wie ihr Grundlaut,
/// ß wie ss, ohne Groß-/Kleinschreibung.
String glossarSchluessel(String titel) => titel
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

/// Einträge, deren Begriff oder Text [suche] enthält (ohne Groß-/Klein),
/// **alphabetisch nach Begriff** (30.10.2026, auf Ansage).
List<GlossarEintrag> glossarSuche(String suche) {
  final q = suche.trim().toLowerCase();
  return [
    for (final g in glossar)
      if (q.isEmpty ||
          g.e.titel.toLowerCase().contains(q) ||
          g.e.text.toLowerCase().contains(q))
        g,
  ]..sort(
    (a, b) =>
        glossarSchluessel(a.e.titel).compareTo(glossarSchluessel(b.e.titel)),
  );
}
