import '../../../app/farben.dart';
import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../../../app/widgets/punktzahl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/h2h_grundlage.dart';
import '../logic/hochrechnung.dart';
import '../logic/naechstes_spiel.dart';
import '../logic/playoff.dart' show kRegularSeasonMatchdays;
import '../logic/saisonverlauf.dart';
import '../logic/spieler_schnitt.dart';
import '../logic/fantasy_scoring_rules.dart';
import '../../../app/widgets/matchup_chevron.dart';
import '../../../core/logic/round_robin.dart';
import 'matchup_lineups.dart';
import '../models/fantasy_models.dart';
import '../models/player_absence.dart';
import '../providers.dart';
import '../../../core/ui/app_avatar.dart';

// MatchUp-Palette (wie in der Übersicht): grün normal, rot solange live.

/// Höhe, die ein [MatchupBanner] mitsamt Rändern braucht.
///
/// Das Karussell im MatchUp-Tab steckt seine Seiten in einen `PageView`, und
/// der braucht eine feste Höhe. Sie stand dort als nackte `224` — als der
/// Punktestand eine eigene Zeile bekam, lief der Kasten um 4 px über und das
/// Gerät zeigte den schwarz-gelben Balken. Eine Zahl, die dem Inhalt
/// hinterherlaufen muss, gehört nicht an zwei Stellen: Sie steht hier, das
/// Karussell liest sie, und `test/matchup_banner_vorschau_test.dart` rendert
/// einen Kasten genau in dieser Höhe — wächst der Inhalt wieder, wird der Test
/// rot statt das Gerät.
// **206 statt 236, seit die Kopfzeile weg ist.** Die Zahl steht hier und
// nicht im Karussell: Sie muss dem Inhalt folgen, und der Inhalt wohnt in
// dieser Datei. Wächst er wieder, meldet die Vorschau
// `matchup_banner_vorschau_test` den Überlauf, bevor es ein Gerät tut.
//
// **176 seit dem Umbau nach Sleeper** (14.10.2026): Jede Seite trägt ihre
// Zahlen jetzt in der eigenen Spalte neben dem Avatar, statt einen
// Punktestand und ein Band in eigenen Zeilen darunter zu stapeln.
const double kMatchupBannerHoehe = 176;

// Das große Chevron als halbtransparentes Wasserzeichen hinter dem Inhalt ist
// **entfernt**. Es lag mit 45 % Deckung quer über Namen und Punktestand und
// machte den Kasten genau das, was er nicht sein soll: undurchsichtig. Auf der
// Liga-Übersicht ist derselbe „halbtransparente Dekor-Chevron" aus demselben
// Grund schon einmal geflogen (siehe CLAUDE.md) — hier war er stehen geblieben.
// Wer ihn zurückholen will, sollte wissen: Er kostet Lesbarkeit an der einzigen
// Stelle des Schirms, an der eine Zahl zählt.

/// Live-MatchUp-Kopf: zeigt die eigene Head-to-Head-Paarung eines Spieltags.
/// Hintergrund grün; solange der Spieltag läuft (erster Anpfiff bis letzter
/// Abpfiff) wird er rot und zeigt den Live-Stand. Tippen tut, was [onTap]
/// sagt. Liegen die Basisdaten nicht vor (kein Login, <2
/// Manager, keine eigene Paarung), wird [fallback] gezeigt.
class MatchupHero extends ConsumerWidget {
  const MatchupHero({
    super.key,
    required this.league,
    required this.round,
    this.fallback = const SizedBox.shrink(),
    this.onTap,
  });

  final FantasyLeague league;
  final int round;
  final Widget fallback;

  /// Was ein Tipp auf den Kasten tut. Auf der Liga-Übersicht: in den
  /// MatchUp-Reiter wechseln (auf Ansage, 14.10.2026) — nicht mehr in die
  /// abgeschlossene Detailseite, die dasselbe Duell ein zweites Mal zeigte.
  /// Ohne Angabe ist der Kasten reine Anzeige — die frühere Detailseite gibt
  /// es nicht mehr.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final myId = ref.watch(currentUserProvider)?.id;

    if (managers == null || pool == null || myId == null) return fallback;

    // Stabile Reihenfolge wie im MatchUp-Tab (Draft-Position, dann User-ID).
    final ids = managers.map((m) => m.userId).toList()
      ..sort((a, b) {
        final ma = managers.firstWhere((m) => m.userId == a);
        final mb = managers.firstWhere((m) => m.userId == b);
        final pa = ma.draftPosition ?? 1 << 30;
        final pb = mb.draftPosition ?? 1 << 30;
        return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
      });
    if (ids.length < 2) return fallback;

    final pairing = roundPairings(
      ids,
      round,
    ).where((m) => m.home == myId || m.away == myId).firstOrNull;
    if (pairing == null) return fallback;

    final nameOf = {for (final m in managers) m.userId: m.display};
    final avatarOf = {
      for (final m in managers)
        m.userId: ManagerAvatar(
          userId: m.userId,
          url: m.avatarUrl,
          emoji: m.avatarEmoji,
          color: m.avatarColor,
        ),
    };
    final roundFx = [
      for (final f in all ?? const <Fixture>[])
        if (f.round == round) f,
    ];
    final live = roundIsLive(roundFx, DateTime.now());
    // Frühester Anpfiff des Spieltags — die Vorschau schreibt ihn unter das
    // „VS".
    final anpfiff = roundFx.isEmpty
        ? null
        : roundFx.map((f) => f.kickoff).reduce((a, b) => a.isBefore(b) ? a : b);
    final allFinished =
        roundFx.isNotEmpty &&
        roundFx.every((f) => f.status == FixtureStatus.finished);
    final started = live || allFinished;

    // Bye: eigener Spieltag spielfrei.
    if (pairing.isBye) {
      return MatchupBanner(
        remisGrenze: league.remisGrenze ?? 0,
        round: round,
        homeName: nameOf[myId] ?? 'Du',
        awayName: null,
        homePoints: 0,
        awayPoints: 0,
        homeMe: true,
        awayMe: false,
        homeAvatar: avatarOf[myId],
        live: live,
        started: started,
        mine: true,
        onTap: onTap,
      );
    }

    final oppId = pairing.home == myId ? pairing.away! : pairing.home;
    final byId = {for (final p in pool) p.id: p};
    final roundStats =
        ref.watch(roundStatsProvider(round)).valueOrNull ??
        const <String, PlayerMatchStats>{};
    final totals = effectiveTotalsForRound(
      stats: roundStats,
      round: round,
      managers: managers,
      roster: roster,
      playerById: byId,
      lineups: lineups,
      scoring: league.scoring,
      rosterConfig: league.roster,
    );

    // **Dieselbe Rechnung wie im MatchUp-Tab, aus derselben Funktion.**
    // `duellPrognose` und `bannerBilanz` stehen einmal da; beide Kästen zeigen
    // damit für dasselbe Duell dieselben Zahlen.
    //
    // **Unbedingt beobachten, nicht im Zweig:** Ein `ref.watch` hinter einer
    // Bedingung meldet die Abhängigkeit ab, sobald der andere Fall greift.
    final saison =
        ref.watch(seasonStatsProvider).valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};
    final abgepfiffen = ref.watch(abgepfiffeneRundenProvider);
    final ausfaelle =
        ref.watch(absencesProvider).valueOrNull ??
        const <String, PlayerAbsence>{};
    final wochenStreuung = ref.watch(fantasyWochenStreuungProvider(league.id));
    final fertig = gewerteteRunden(abgepfiffen, saison.keys);
    final saisonGewertet = {
      for (final e in saison.entries)
        if (fertig.contains(e.key)) e.key: e.value,
    };
    final grundlage = h2hGrundlage(
      league: league,
      managers: managers,
      roster: roster,
      lineups: lineups,
      playerById: byId,
      seasonStats: saison,
      abgepfiffen: abgepfiffen,
    );

    MatchupSideData seite(String id) => computeSideData(
      league: league,
      round: round,
      managerId: id,
      byId: byId,
      roster: roster,
      lineups: lineups,
      stats: roundStats,
    );
    final prognose = duellPrognose(
      round: round,
      heim: seite(myId),
      gast: seite(oppId),
      spiele: all ?? const <Fixture>[],
      saisonGewertet: saisonGewertet,
      regeln: league.scoring,
      ausfaelle: ausfaelle,
      wochenStreuung: wochenStreuung,
      jetzt: DateTime.now(),
    );

    return MatchupBanner(
      remisGrenze: league.remisGrenze ?? 0,
      round: round,
      homeName: nameOf[myId] ?? 'Du',
      awayName: nameOf[oppId] ?? '?',
      homePoints: totals[myId] ?? 0.0,
      awayPoints: totals[oppId] ?? 0.0,
      homeMe: true,
      awayMe: false,
      homeAvatar: avatarOf[myId],
      awayAvatar: avatarOf[oppId],
      live: live,
      anpfiff: anpfiff,
      started: started,
      mine: true,
      homeBilanz: bannerBilanz(grundlage, myId),
      awayBilanz: bannerBilanz(grundlage, oppId),
      homeErwartet: prognose.heimErwartet,
      awayErwartet: prognose.gastErwartet,
      siegchanceHeim: prognose.siegchanceHeim,
      onTap: onTap,
    );
  }
}

/// Gemeinsamer Rahmen des MatchUp-Kopfs (Farbverlauf, Kopfzeile mit Spieltag
/// und Status-Pille, Marken-Wasserzeichen, Tap → Detail).
class HeroShell extends StatelessWidget {
  const HeroShell({
    super.key,
    required this.accent,
    required this.live,
    required this.started,
    required this.onTap,
    required this.child,
  });

  final Color accent;
  final bool live;

  /// Ist der Spieltag angepfiffen? Steuert, wie viel Farbe der Kasten trägt.
  final bool started;

  /// `null` heißt: Der Kasten ist eine Anzeige, kein Knopf — ohne Tinte.
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grund = Theme.of(context).cardColor;
    // **Der Akzent füllt nicht die Fläche, er haucht aus der Ecke** — dasselbe
    // Muster wie bei den Ligakarten auf dem Startbildschirm
    // (`_kartenFlaeche`). Kräftig, solange live; leiser sonst.
    //
    // **Auch die Vorschau trägt den Hauch.** Sie war eine Zeit lang ganz ohne,
    // nach der Regel „Farbe nur, wo etwas ansteht" — und war damit die einzige
    // graue Karte auf einem Schirm voller Zustände. Auf Ansage wieder
    // eingefärbt, in derselben Stärke wie ein beendeter Spieltag:
    // Unterschieden werden die beiden ohnehin deutlicher durch Marke
    // („Vorschau" gegen „Beendet"), Punktestand und Balken.
    // Auf Weiß trägt Farbe viel stärker als auf Schwarz — derselbe Anteil
    // machte den Kasten im hellen Modus rosa. Dort halb so viel.
    final staerke = context.istHell ? 0.5 : 1.0;
    final hauch = live
        ? accent.withValues(alpha: 0.22 * staerke)
        : accent.withValues(alpha: 0.10 * staerke);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          // Ohne Kopfzeile darf der Kasten flacher sein; bei einem
          // spielfreien Spieltag stand sonst ein leeres Drittel darunter.
          constraints: const BoxConstraints(minHeight: 122),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: grund,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.75],
              colors: [Color.alphaBlend(hauch, grund), grund],
            ),
            // **Eine Kante für alle Karten**, auch während des Spieltags.
            // Der farbige Rand bei „live" war der lauteste Strich des
            // Schirms und stand neben zwei Karten mit Haarlinie — drei
            // Behandlungen für dieselbe Sorte Objekt. Dass etwas läuft,
            // sagen der kräftigere Hauch aus der Ecke, der rote Punkt und
            // das Wort „LIVE"; eine Linie sagt es nicht besser.
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // **Das Stadion der Startseite, schlicht** (20.10.2026, auf
                // Ansage). Dasselbe Bild wie hinter der Kopfkarte, aber nur
                // zu 30 % — der Kasten trägt Zahlen, und die brauchen ruhigen
                // Grund. Unterer Bildrand (beleuchteter Rasen mit Linien),
                // nur im dunklen Modus: Das Foto ist fast schwarz.
                // Im hellen Modus dasselbe Bild unter einem weißen Schleier —
                // sichtbar, aber hell (29.10.2026, auf Ansage).
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: context.istHell ? 1 : 0.30,
                      child: context.istHell
                          ? Image.asset(
                              'assets/images/spiel_linien.png',
                              fit: BoxFit.cover,
                              alignment: Alignment.bottomCenter,
                            )
                          : Image.asset(
                              'assets/images/spiel_bg.jpg',
                              fit: BoxFit.cover,
                              alignment: Alignment.bottomCenter,
                            ),
                    ),
                  ),
                ),
                // **Keine Kopfzeile mehr.** Sie trug ein Blitzsymbol, das Wort
                // MATCHUP, den Spieltag und eine Status-Pille — vier
                // Auskünfte in 11 bis 13 Punkt über dem, worum es geht.
                // Gemeldet als „zu viel kleine Schrift", und der Kasten
                // steht ohnehin in einem Zusammenhang, der den Spieltag
                // nennt (Spieltagswähler im MatchUp-Reiter, Kopf der
                // Liga-Übersicht). Dass etwas läuft, sagen jetzt der
                // kräftigere Hauch, die roten Zahlen und das Wort
                // „Live-Punkte" unter dem Balken.
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Center(child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Profildaten eines Managers, so wie sie im Banner gebraucht werden.
///
/// Ein eigener kleiner Typ statt vier loser Parameter je Seite: Acht
/// Argumente an einem Konstruktor sind acht Gelegenheiten, Heim und Gast zu
/// vertauschen.
class ManagerAvatar {
  const ManagerAvatar({this.userId, this.url, this.emoji, this.color});

  final String? userId;
  final String? url;
  final String? emoji;
  final String? color;
}

/// Runder Manager-Avatar im Banner: **das Profilbild des Kontos**, im
/// Banner-Akzent geringt; der Nicht-Führende wird gedimmt.
///
/// **Vorher stand hier ein Kreis mit dem Anfangsbuchstaben** — selbst
/// gezeichnet, obwohl die App mit [AppAvatar] längst einen Baustein für genau
/// diese Frage hat (Bild, sonst Emoji, sonst ein aus der Nutzer-ID erzeugtes
/// Standardbild). Im Seitenmenü, im Ligaprofil und in der Teamliste stand das
/// echte Bild, ausgerechnet im Duell nicht. Gemeldet als „im MatchUp-Tab
/// bitte die Account-Profilbilder statt der Kreise mit den Buchstaben".
///
/// Ring und Schein bleiben: Sie tragen den Zustand („wer führt"), und den
/// kennt [AppAvatar] nicht — er weiß nur, wie ein Mensch aussieht.
class HeroAvatar extends StatelessWidget {
  const HeroAvatar({
    super.key,
    required this.name,
    required this.accent,
    this.dim = false,
    this.imageUrl,
    this.emoji,
    this.colorHex,
    this.userId,
  });

  final String name;
  final Color accent;
  final bool dim;

  /// Die drei Felder des Profils. Fehlen sie alle, erzeugt [AppAvatar] aus
  /// [userId] (sonst dem Namen) ein stabiles Standardbild — dasselbe, das der
  /// Nutzer überall sonst in der App hat.
  final String? imageUrl;
  final String? emoji;
  final String? colorHex;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: dim ? context.farben.vorne.withValues(alpha: 0.28) : accent,
          width: 2.5,
        ),
        boxShadow: dim
            ? null
            : [
                BoxShadow(
                  color: accent.withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: -3,
                ),
              ],
      ),
      // **Der Ring bleibt sichtbar, das Bild sitzt darin.** Ohne das Polster
      // liefe das Bild unter den Rand und der Zustand wäre weg.
      child: Padding(
        padding: const EdgeInsets.all(2.5),
        child: Opacity(
          opacity: dim ? 0.55 : 1,
          child: AppAvatar(
            imageUrl: imageUrl,
            emoji: emoji,
            colorHex: colorHex,
            fallbackText: name,
            seed: userId,
            size: 41,
          ),
        ),
      ),
    );
  }
}

/// Grau, solange niemand Favorit ist.
const kChanceNeutral = Color(0xFF9AA0AA);

/// **Die Farbregel für Band und Prozentzahlen — an einer Stelle.**
///
/// Beide zeigen dieselbe Auskunft; liefe die Regel zweimal getrennt, könnte
/// das Band grau bleiben, während die Zahlen einen Favoriten ausrufen. Genau
/// diese Sorte Doppelung ist in diesem Projekt schon mehrfach auseinander-
/// gelaufen.
///
/// **Unter drei Prozentpunkten Unterschied ist niemand Favorit.** 51 zu 49 ist
/// ein Münzwurf, und ihn grün gegen rot zu stellen behauptet eine Überlegen-
/// heit, die im Rauschen liegt.
(Color, Color) chanceFarben(
  int linksProzent, [
  MatchUpFarben f = MatchUpFarben.dunkel,
]) {
  final rechtsProzent = 100 - linksProzent;
  if ((linksProzent - rechtsProzent).abs() < 3) {
    return (f.neutral, f.neutral);
  }
  return linksProzent > rechtsProzent ? (f.gruen, f.rot) : (f.rot, f.gruen);
}

// ---------------------------------------------------------------------------
// Prognose und Bilanz eines Duells — einmal gerechnet, an beiden Orten benutzt
// ---------------------------------------------------------------------------

/// Hochrechnung beider Seiten und die Siegchance der Heimseite.
typedef DuellPrognose = ({
  double? heimErwartet,
  double? gastErwartet,
  double? siegchanceHeim,
});

/// **Was der Kasten über ein Duell sagt, das noch nicht entschieden ist.**
///
/// Vor dem Anpfiff ist das die Prognose (Summe der Schnitte), währenddessen
/// die Hochrechnung (echte Punkte plus erwarteter Rest, `hochrechnung.dart`).
///
/// **Nach dem letzten Abpfiff wieder die Prognose von vor dem Spieltag**
/// (19.10.2026, auf Ansage) — zum Vergleich mit dem Endstand. Gespeichert ist
/// sie nirgends; sie wird nachgerechnet, wie sie damals stand: nur Spieltage
/// **vor** diesem, jeder Spieler „noch nicht angepfiffen", und nur Ausfälle,
/// die schon vor dem ersten Anpfiff gemeldet waren. Ohne diese drei Schnitte
/// rechnete sie mit dem Spieltag selbst und läge mal über, mal unter dem, was
/// am Freitag dastand. Die Siegchance zählt nach dem Spieltag nicht mehr — der
/// Kasten zeigt dort Sieg oder Niederlage.
///
/// **Steht hier und nicht in zwei Schirmen**, weil der Kasten an zwei Orten
/// erscheint (Liga-Übersicht, MatchUp-Karussell) und für dasselbe Duell
/// dieselbe Zahl zeigen muss.
///
/// [saisonGewertet] sind nur **abgepfiffene** Spieltage (`gewerteteRunden`) —
/// der laufende trägt Zwischenstände und würde jeden Schnitt drücken. Ohne
/// einen einzigen gewerteten Spieltag gibt es keine Grundlage, und alles ist
/// `null`: eine erfundene Zahl wäre schlechter als keine.
DuellPrognose duellPrognose({
  required int round,
  required MatchupSideData heim,
  required MatchupSideData? gast,
  required List<Fixture> spiele,
  required Map<int, Map<String, PlayerMatchStats>> saisonGewertet,
  required FantasyScoringRules regeln,
  required Map<String, PlayerAbsence> ausfaelle,
  required double? wochenStreuung,
  required DateTime jetzt,
}) {
  const nichts = (heimErwartet: null, gastErwartet: null, siegchanceHeim: null);

  final dieser = [
    for (final f in spiele)
      if (f.round == round) f,
  ];
  final vorSpieltag = rundeDurch(dieser, jetzt);
  if (vorSpieltag) {
    final ersterAnpfiff = dieser
        .map((f) => f.kickoff)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    saisonGewertet = {
      for (final e in saisonGewertet.entries)
        if (e.key < round) e.key: e.value,
    };
    ausfaelle = {
      for (final e in ausfaelle.entries)
        if ((e.value.seit == null || e.value.seit!.isBefore(ersterAnpfiff)) &&
            !(e.value.ausgewechselt && (e.value.runde ?? 0) >= round))
          e.key: e.value,
    };
    jetzt = ersterAnpfiff.subtract(const Duration(minutes: 1));
  }

  if (gast == null || saisonGewertet.values.every((r) => r.isEmpty)) {
    return nichts;
  }
  Hochrechnung rechne(MatchupSideData seite) => hochrechnung([
    for (final p in seite.starters)
      () {
        final spiel = naechstesSpiel(spiele, round, p.club);
        final lage = spiel == null
            ? SpielLage.ohneSpiel
            : vorSpieltag
            ? SpielLage.offen
            : spiel.status == FixtureStatus.finished
            ? SpielLage.fertig
            : !spiel.anpfiff.isAfter(jetzt)
            ? SpielLage.laeuft
            : SpielLage.offen;
        return HochrechnungsPosten(
          lage: lage,
          punkte: seite.points[p.id] ?? 0,
          schnitt: spielerSchnitt(
            saison: saisonGewertet,
            spielerId: p.id,
            position: p.position,
            regeln: regeln,
          ).schnitt,
          anpfiff: spiel?.anpfiff,
          faellt: ausfaelle.containsKey(p.id),
        );
      }(),
  ], jetzt: jetzt);
  final h = rechne(heim);
  final g = rechne(gast);
  return (
    heimErwartet: h.erwartet,
    gastErwartet: g.erwartet,
    siegchanceHeim: siegchanceLive(
      heim: h,
      gast: g,
      wochenStreuung: wochenStreuung,
    ),
  );
}

/// Die Zeile unter dem Namen: Platz und Bilanz, dazu die Serie.
typedef BannerBilanz = ({String? zeile, BannerSerie? serie});

/// Serie: Ausgang und wie oft hintereinander.
typedef BannerSerie = ({DuellAusgang ausgang, int anzahl});

/// Platz, Bilanz (S-U-N) und Serie eines Managers — aus derselben
/// [h2hGrundlage] wie die Tabelle, damit beide dasselbe sagen.
BannerBilanz bannerBilanz(H2HGrundlage g, String managerId) {
  final standings = h2hStandings(
    g.ids,
    g.summen,
    remisGrenze: g.remis,
    bilanz: g.bilanz,
  );
  if (standings.every((r) => r.played == 0)) return (zeile: null, serie: null);
  final i = standings.indexWhere((r) => r.managerId == managerId);
  if (i < 0) return (zeile: null, serie: null);
  final r = standings[i];
  final verlauf = saisonverlauf(
    ids: g.ids,
    managerId: managerId,
    gewertet: g.summen,
    letzteRunde: kRegularSeasonMatchdays,
    remisGrenze: g.remis,
  );
  return (
    // Ohne Remis-Regel die NFL-Bilanz (S-N), sonst S-U-N.
    zeile: g.bilanz
        ? 'P${i + 1} · ${r.nflBilanz}'
        : 'P${i + 1} · ${r.wins}-${r.ties}-${r.losses}',
    serie: serie(verlauf),
  );
}

// ---------------------------------------------------------------------------
// Der Kasten
// ---------------------------------------------------------------------------

/// Ein MatchUp-Kasten für eine **beliebige** Paarung (Heim gegen Gast).
///
/// **Aufbau nach dem Vorbild Sleeper** (Screenshot vom 14.10.2026): Jede Seite
/// trägt ihre eigene Spalte — Avatar, groß der Stand, klein darunter, wo es
/// hinläuft, dann die Siegchance in Prozent mit einem Balken nur für diese
/// Seite, zuletzt Name, Platz, Bilanz und Serie. In der Mitte steht das
/// MatchUp-Zeichen und der Zustand des Spieltags.
///
/// Der Vorgänger stellte den Punktestand mittig auf eine eigene Zeile und die
/// Siegchance als ein gemeinsames Band darunter. Das las sich als Tauziehen,
/// aber man musste jede Zahl erst ihrer Seite zuordnen. Hier gehört alles,
/// was über eine Mannschaft gesagt wird, in ihre Spalte.
///
/// **Was groß steht, hängt am Zustand:**
///
/// | Zustand | groß | klein |
/// |---|---|---|
/// | vor dem Anpfiff | Prognose, gedämpft | „Prognose" |
/// | läuft | Stand | „Prognose 190,2" (Hochrechnung) |
/// | beendet | Endstand | „Endstand" |
///
/// Vor dem Anpfiff steht **keine 0** groß da: Es ist noch kein Ball gerollt,
/// und eine Null sähe aus wie ein Ergebnis. Die Prognose dagegen ist gedämpft
/// und beschriftet — gemeldet war einmal, dass man sie sonst für feste Punkte
/// hält.
class MatchupBanner extends StatelessWidget {
  const MatchupBanner({
    super.key,
    required this.round,
    required this.homeName,
    required this.awayName,
    required this.homePoints,
    required this.awayPoints,
    required this.homeMe,
    required this.awayMe,
    this.homeAvatar,
    this.awayAvatar,
    required this.live,
    required this.started,
    this.onTap,
    this.mine = false,
    this.homeBilanz,
    this.awayBilanz,
    this.anpfiff,
    this.homeErwartet,
    this.awayErwartet,
    this.siegchanceHeim,
    this.onHomeName,
    this.onAwayName,
    this.remisGrenze = 0,
  });

  /// Höchster Abstand, der noch Unentschieden ist (Ligaeinstellung) — damit
  /// „Sieg" im Kasten dasselbe meint wie in der Tabelle.
  final num remisGrenze;

  final int round;
  final String homeName;

  /// `null` heißt spielfrei.
  final String? awayName;
  final double homePoints;
  final double awayPoints;
  final bool homeMe;
  final bool awayMe;
  final ManagerAvatar? homeAvatar;
  final ManagerAvatar? awayAvatar;
  final bool live;
  final bool started;
  final bool mine;

  /// `null` im MatchUp-Tab: Dort ist man schon, ein Tipp führt nirgendwohin.
  final VoidCallback? onTap;

  /// Platz, Bilanz und Serie je Seite — `null`, solange nichts gewertet ist.
  final BannerBilanz? homeBilanz;
  final BannerBilanz? awayBilanz;

  /// Erster Anpfiff des Spieltags — steht vor dem Spieltag in der Mitte.
  final DateTime? anpfiff;

  /// Prognose (vor dem Anpfiff) bzw. Hochrechnung (während des Spieltags).
  final double? homeErwartet;
  final double? awayErwartet;

  /// Wahrscheinlichkeit, dass die **Heimseite** gewinnt (0–1), oder `null`.
  final double? siegchanceHeim;

  /// Tipp auf Bild oder Name einer Seite — im MatchUp-Tab das Ligaprofil des
  /// Teilnehmers. `null`: Bild und Name gehören zum Tipp-Ziel des Kastens.
  final VoidCallback? onHomeName;
  final VoidCallback? onAwayName;

  @override
  Widget build(BuildContext context) {
    final accent = live ? context.farben.rot : context.farben.gruen;
    final beendet = started && !live;

    if (awayName == null) {
      return HeroShell(
        accent: accent,
        live: live,
        started: started,
        onTap: onTap,
        child: Row(
          children: [
            _Tippbar(
              onTap: onHomeName,
              child: HeroAvatar(
                name: homeName,
                accent: accent,
                imageUrl: homeAvatar?.url,
                emoji: homeAvatar?.emoji,
                colorHex: homeAvatar?.color,
                userId: homeAvatar?.userId,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Tippbar(
                onTap: onHomeName,
                child: _NameZeilen(
                  name: homeName,
                  me: homeMe,
                  bilanz: homeBilanz,
                  links: true,
                ),
              ),
            ),
            Text(
              'spielfrei',
              style: TextStyle(
                fontSize: Schrift.titel,
                fontWeight: FontWeight.w700,
                color: context.farben.vorne.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    final chanceLinks = siegchanceHeim;
    final chanceRechts = chanceLinks == null ? null : 1 - chanceLinks;
    return HeroShell(
      accent: accent,
      live: live,
      started: started,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Seite(
              links: true,
              name: homeName,
              me: homeMe,
              avatar: homeAvatar,
              punkte: homePoints,
              gegnerPunkte: awayPoints,
              erwartet: homeErwartet,
              chance: chanceLinks,
              started: started,
              beendet: beendet,
              remisGrenze: remisGrenze,
              bilanz: homeBilanz,
              onName: onHomeName,
            ),
          ),
          _Mitte(live: live, started: started, anpfiff: anpfiff),
          Expanded(
            child: _Seite(
              links: false,
              name: awayName!,
              me: awayMe,
              avatar: awayAvatar,
              punkte: awayPoints,
              gegnerPunkte: homePoints,
              erwartet: awayErwartet,
              chance: chanceRechts,
              started: started,
              beendet: beendet,
              remisGrenze: remisGrenze,
              bilanz: awayBilanz,
              onName: onAwayName,
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Spalte des Kastens — alles, was über eine Mannschaft gesagt wird.
class _Seite extends StatelessWidget {
  const _Seite({
    required this.links,
    required this.name,
    required this.me,
    required this.avatar,
    required this.punkte,
    required this.gegnerPunkte,
    required this.erwartet,
    required this.chance,
    required this.started,
    required this.beendet,
    required this.bilanz,
    this.onName,
    this.remisGrenze = 0,
  });

  final num remisGrenze;

  final bool links;
  final String name;
  final bool me;
  final VoidCallback? onName;
  final ManagerAvatar? avatar;
  final double punkte;
  final double gegnerPunkte;
  final double? erwartet;
  final double? chance;
  final bool started;
  final bool beendet;
  final BannerBilanz? bilanz;

  @override
  Widget build(BuildContext context) {
    final ausgang = duellErgebnis(
      punkte,
      gegnerPunkte,
      remisGrenze: remisGrenze,
    );
    final verloren = beendet && ausgang < 0;
    final ausrichtung = links
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;

    // Groß: der Stand — vor dem Anpfiff die Prognose, gedämpft.
    final Widget gross;
    if (started) {
      gross = Punktzahl(
        punkte,
        stil: TextStyle(
          fontSize: Schrift.gross,
          fontWeight: FontWeight.w800,
          height: 1,
          color: context.farben.vorne.withValues(alpha: verloren ? 0.6 : 1),
        ),
      );
    } else if (erwartet != null) {
      gross = Punktzahl(
        erwartet!,
        stil: TextStyle(
          fontSize: Schrift.gross,
          fontWeight: FontWeight.w800,
          height: 1,
          color: context.farben.vorne.withValues(alpha: 0.55),
        ),
      );
    } else {
      gross = Text(
        '–',
        style: TextStyle(
          fontSize: Schrift.gross,
          fontWeight: FontWeight.w800,
          height: 1,
          color: context.farben.vorne.withValues(alpha: 0.4),
        ),
      );
    }

    // Klein darunter: was die große Zahl ist, bzw. wo es hinläuft.
    // **Nach dem Spieltag nur die Zahl** (27.10.2026, auf Ansage: erst die
    // Prognose von vorher weg, dann auch das Wort „Endstand"). Dass es der
    // Endstand ist, sagt SIEG/NIEDERLAGE darunter.
    final klein = beendet
        ? ''
        : started
        ? (erwartet == null ? 'Live' : 'Prognose ${formatPoints(erwartet!)}')
        : (erwartet == null ? '' : 'Prognose');

    final zahlen = Column(
      crossAxisAlignment: ausrichtung,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: gross),
        const SizedBox(height: 4),
        // **Verkleinern statt abschneiden** — „Prognose 1284,6" ist die
        // längste Zeile, und abgeschnitten hieße sie „Prognose 128".
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            klein,
            maxLines: 1,
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w600,
              height: 1,
              color: context.farben.vorne.withValues(alpha: 0.5),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );

    final bild = _Tippbar(
      onTap: onName,
      child: HeroAvatar(
        name: name,
        accent: me
            ? context.farben.gruen
            : context.farben.vorne.withValues(alpha: 0.35),
        dim: verloren,
        imageUrl: avatar?.url,
        emoji: avatar?.emoji,
        colorHex: avatar?.color,
        userId: avatar?.userId,
      ),
    );

    return Column(
      crossAxisAlignment: ausrichtung,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: links
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          children: links
              ? [bild, const SizedBox(width: 10), Flexible(child: zahlen)]
              : [Flexible(child: zahlen), const SizedBox(width: 10), bild],
        ),
        const SizedBox(height: 10),
        _ChanceZeile(
          links: links,
          chance: chance,
          beendet: beendet,
          sieg: beendet && ausgang > 0,
          niederlage: verloren,
        ),
        const SizedBox(height: 10),
        _Tippbar(
          onTap: onName,
          child: _NameZeilen(name: name, me: me, bilanz: bilanz, links: links),
        ),
      ],
    );
  }
}

/// Siegchance einer Seite: „63 % Sieg" und ein Balken, der nur ihr gehört.
///
/// **Grün für den Favoriten, rot für den anderen, grau bei einem Münzwurf** —
/// dieselbe Farbregel wie zuvor (`chanceFarben`), nur je Seite angewandt.
/// Ist der Spieltag beendet, steht dort das Ergebnis als Wort.
class _ChanceZeile extends StatelessWidget {
  const _ChanceZeile({
    required this.links,
    required this.chance,
    required this.beendet,
    required this.sieg,
    required this.niederlage,
  });

  final bool links;
  final double? chance;
  final bool beendet;
  final bool sieg;
  final bool niederlage;

  @override
  Widget build(BuildContext context) {
    final String text;
    final double anteil;
    final Color farbe;
    if (beendet) {
      text = sieg ? 'Sieg' : (niederlage ? 'Niederlage' : 'Unentschieden');
      anteil = sieg ? 1 : (niederlage ? 0 : 0.5);
      farbe = sieg
          ? context.farben.gruen
          : (niederlage ? context.farben.rot : context.farben.neutral);
    } else if (chance != null) {
      final prozent = (chance! * 100).round().clamp(0, 100);
      text = '$prozent % Sieg';
      anteil = chance!;
      farbe = chanceFarben(prozent.clamp(1, 99), context.farben).$1;
    } else {
      // Ohne Grundlage keine Zahl — aber dieselbe Höhe, damit beide Seiten
      // und alle Karten des Karussells gleich stehen.
      return const SizedBox(height: 18);
    }
    return SizedBox(
      height: 18,
      child: Column(
        crossAxisAlignment: links
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              height: 1,
              color: farbe,
            ),
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(
                    color: context.farben.vorne.withValues(alpha: 0.08),
                  ),
                  // Der Balken wächst von der Außenkante nach innen.
                  Align(
                    alignment: links
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: anteil.clamp(0.0, 1.0),
                      child: Container(color: farbe),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Eigenes Tipp-Ziel innerhalb des Kastens — ohne [onTap] durchlässig, dann
/// gilt der Tipp dem ganzen Kasten.
class _Tippbar extends StatelessWidget {
  const _Tippbar({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: child,
    );
  }
}

/// Name und darunter Platz · Bilanz · Serie.
class _NameZeilen extends StatelessWidget {
  const _NameZeilen({
    required this.name,
    required this.me,
    required this.bilanz,
    required this.links,
  });

  final String name;
  final bool me;
  final BannerBilanz? bilanz;
  final bool links;

  @override
  Widget build(BuildContext context) {
    final leise = context.farben.vorne.withValues(alpha: 0.55);
    final serie = bilanz?.serie;
    final (pfeil, buchstabe, farbe) = switch (serie?.ausgang) {
      DuellAusgang.sieg => ('▲', 'S', context.farben.gruen),
      DuellAusgang.niederlage => ('▼', 'N', context.farben.rot),
      _ => ('■', 'U', context.farben.neutral),
    };
    return Column(
      crossAxisAlignment: links
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: links ? TextAlign.start : TextAlign.end,
          style: TextStyle(
            fontSize: Schrift.titel,
            fontWeight: me ? FontWeight.w800 : FontWeight.w700,
            height: 1.15,
            color: context.farben.vorne,
          ),
        ),
        if (bilanz?.zeile != null) ...[
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: bilanz!.zeile),
                if (serie != null) ...[
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: '$pfeil${serie.anzahl}$buchstabe',
                    style: TextStyle(color: farbe, fontWeight: FontWeight.w800),
                  ),
                ],
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: links ? TextAlign.start : TextAlign.end,
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w600,
              height: 1.1,
              color: leise,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

/// Die Mitte: das MatchUp-Zeichen und darunter der Zustand des Spieltags.
class _Mitte extends StatelessWidget {
  const _Mitte({
    required this.live,
    required this.started,
    required this.anpfiff,
  });

  final bool live;
  final bool started;
  final DateTime? anpfiff;

  @override
  Widget build(BuildContext context) {
    final String? zustand = live
        ? 'LIVE'
        : started
        ? 'ENDE'
        : (anpfiff == null ? null : anpfiffKurz(anpfiff!.toLocal()));
    return SizedBox(
      width: 46,
      child: Column(
        children: [
          const SizedBox(height: 4),
          // **Nur das Zeichen, ohne Kästchen** (20.10.2026, auf Ansage) —
          // dieselbe Linie wie bei den Ligakarten. Etwas größer, damit es
          // ohne Fläche dahinter trotzdem trägt.
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            child: const MatchUpChevron(size: 26),
          ),
          if (zustand != null) ...[
            const SizedBox(height: 6),
            Text(
              zustand,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: Schrift.mikro,
                fontWeight: FontWeight.w800,
                letterSpacing: live ? 1 : 0.3,
                height: 1.2,
                color: live
                    ? context.farben.rot
                    : context.farben.vorne.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
