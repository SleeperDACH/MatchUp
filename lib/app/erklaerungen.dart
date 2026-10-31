/// **Kurze Erklärungen hinter dem Fragezeichen** (29.10.2026, Punkt 3 der
/// Nutzer-Analyse: „keine langen Texte — lieber ein kleines Fragezeichen, wo
/// Erklärungen aufpoppen").
///
/// Je Begriff ein Titel und höchstens drei Sätze. Sie stehen hier zusammen,
/// damit derselbe Begriff überall gleich erklärt wird — auf dem Homescreen
/// und beim Anlegen.
typedef Erklaerung = ({String titel, String text});

const Erklaerung erklaerungFantasy = (
  titel: 'Fantasy-Liga',
  text:
      'Zu Saisonbeginn verteilt ihr im Draft die echten Bundesliga-Spieler '
      'reihum unter euch — jeder Spieler gehört nur einem Team. Deine Spieler '
      'sammeln Punkte für ihre Leistung am Wochenende (Tore, Vorlagen, '
      'Zweikämpfe), und jeden Spieltag spielst du im Duell gegen ein anderes '
      'Team deiner Liga. Über Trades und freie Spieler baust du dein Team die '
      'Saison über um.',
);

const Erklaerung erklaerungDraft = (
  titel: 'Draft',
  text:
      'Zu Saisonbeginn werden die Spieler reihum verteilt: Jedes Team wählt '
      'abwechselnd einen. Jeder Spieler gehört nur einem Team. Niemand muss '
      'dafür gleichzeitig online sein — wer zu lange braucht, bekommt '
      'automatisch einen Spieler.',
);

// **Keine Punktzahlen hier:** Sie stellt jede Tipprunde selbst ein. Feste
// Punkte gibt es nur im Globalen Tippspiel (siehe unten).
const Erklaerung erklaerungTippspiel = (
  titel: 'Tippspiel',
  text:
      'Du tippst die Ergebnisse der Spiele vor dem Anpfiff. Wie viele '
      'Punkte es für das exakte Ergebnis, die richtige Tordifferenz oder den '
      'richtigen Sieger gibt, legt der Ersteller der Tipprunde fest — dazu '
      'wahlweise Extras wie Quoten-Bonus oder Bonustipps. Gespielt wird mit '
      'Freunden, die du einlädst.',
);

// Die Punkte stehen hier, weil sie fest sind: Standardwertung aus 0150.
const Erklaerung erklaerungGlobal = (
  titel: 'Globales Tippspiel',
  text:
      'Ein Tippspiel für alle MatchUp-Nutzer, nur mit der 1. Bundesliga. '
      'Die Punkte sind fest: exaktes Ergebnis 4, richtige Tordifferenz 3, '
      'richtiger Sieger 2. Ein Tipp auf „Mitspielen", und du misst dich mit '
      'allen.',
);

// ---------------------------------------------------------------------
// Einstellungen beim Anlegen (Punkt 4 der Nutzer-Analyse): Die Abschnitte
// unter „Weitere Einstellungen" tragen je ein Fragezeichen.
// ---------------------------------------------------------------------

const Erklaerung erklaerungSichtbarkeit = (
  titel: 'Sichtbarkeit',
  text:
      'Privat: Beitreten kann nur, wer den Einladungslink oder Code hat. '
      'Öffentlich: Man findet sie in der Suche. Mit „Nur auf Einladung" '
      'bestätigst du jeden Beitritt selbst.',
);

const Erklaerung erklaerungUnentschieden = (
  titel: 'Unentschieden',
  text:
      'Liegen zwei Teams im Duell nur wenige Punkte auseinander, endet es '
      'unentschieden statt mit einem knappen Sieg. Ausgeschaltet zählen nur '
      'Siege und Niederlagen: Die Tabelle steht dann nach Bilanz (etwa 5-2) '
      'wie in der NFL statt nach Punkten.',
);

const Erklaerung erklaerungWinterpause = (
  titel: 'Reset zur Winterpause',
  text:
      'Am 24.12. werden alle Kader geleert, und es gibt einen zweiten Draft '
      'für die Rückrunde — der Tabellenletzte wählt zuerst. Die Tabelle '
      'bleibt. Picks für diesen Draft lassen sich schon in der Hinrunde '
      'tauschen.',
);

const Erklaerung erklaerungPlayoffs = (
  titel: 'Playoffs',
  text:
      'Am Saisonende spielen die besten Teams der Tabelle im K.-o.-System '
      'um den Titel. Nach der Trade-Deadline sind keine Tausche mehr '
      'möglich.',
);

const Erklaerung erklaerungKaderLimits = (
  titel: 'Kader-Limits',
  text:
      'Höchstzahl je Position im Kader, etwa höchstens zwei Torhüter. Ohne '
      'Limit darf jedes Team so viele Spieler einer Position haben, wie es '
      'will.',
);

const Erklaerung erklaerungVereinsLimit = (
  titel: 'Vereins-Limit',
  text:
      'Höchstens so viele Spieler desselben Bundesliga-Vereins pro Kader, '
      'etwa drei von Bayern. So kann niemand eine ganze Mannschaft '
      'zusammenkaufen.',
);

const Erklaerung erklaerungLigaTippspiel = (
  titel: 'Ligainternes Tippspiel',
  text:
      'Zusätzlich zur Fantasy-Liga tippen alle Mitglieder die Spiele — mit '
      'eigener Tabelle, erreichbar über die Liga.',
);

const Erklaerung erklaerungPunkteJeTipp = (
  titel: 'Punkte je Tipp',
  text:
      'Was ein Tipp bringt: für das exakte Ergebnis, die richtige '
      'Tordifferenz (2:1 getippt, 3:2 gespielt) oder nur den richtigen '
      'Sieger. Für einen falschen Tipp kannst du Minuspunkte vergeben.',
);

const Erklaerung erklaerungModi = (
  titel: 'Modi',
  text:
      'Extras zum Dazuschalten: Bonuspunkte für richtige Tipps auf '
      'Außenseiter, einen Bonus für den einzigen exakten Treffer, Duelle je '
      'Spieltag und Bonustipps auf die Saison wie Meister und Absteiger.',
);
