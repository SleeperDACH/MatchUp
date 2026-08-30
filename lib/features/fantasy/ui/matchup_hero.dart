import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../../../core/logic/round_robin.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'matchup_detail_screen.dart';

// MatchUp-Palette (wie in der Übersicht): grün normal, rot solange live.
const _cGreen = Color(0xFF4ADE6A);
const _cRed = Color(0xFFF23030);

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
const double kMatchupBannerHoehe = 236;

// Das große Chevron als halbtransparentes Wasserzeichen hinter dem Inhalt ist
// **entfernt**. Es lag mit 45 % Deckung quer über Namen und Punktestand und
// machte den Kasten genau das, was er nicht sein soll: undurchsichtig. Auf der
// Liga-Übersicht ist derselbe „halbtransparente Dekor-Chevron" aus demselben
// Grund schon einmal geflogen (siehe CLAUDE.md) — hier war er stehen geblieben.
// Wer ihn zurückholen will, sollte wissen: Er kostet Lesbarkeit an der einzigen
// Stelle des Schirms, an der eine Zahl zählt.

/// Live-MatchUp-Kopf: zeigt die eigene Head-to-Head-Paarung eines Spieltags.
/// Hintergrund grün; solange der Spieltag läuft (erster Anpfiff bis letzter
/// Abpfiff) wird er rot und zeigt den Live-Stand. Tippen springt in die
/// MatchUp-Detailseite. Liegen die Basisdaten nicht vor (kein Login, <2
/// Manager, keine eigene Paarung), wird [fallback] gezeigt.
class MatchupHero extends ConsumerWidget {
  const MatchupHero({
    super.key,
    required this.league,
    required this.round,
    this.fallback = const SizedBox.shrink(),
  });

  final FantasyLeague league;
  final int round;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
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

    final pairing = roundPairings(ids, round)
        .where((m) => m.home == myId || m.away == myId)
        .firstOrNull;
    if (pairing == null) return fallback;

    final nameOf = {for (final m in managers) m.userId: m.display};
    // Tap auf den Kopf → Detailseite der eigenen Paarung (ich immer „Heim").
    void openDetail(String? oppId, String? oppName) => showMatchupDetail(
          context,
          league: league,
          round: round,
          homeId: myId,
          homeName: nameOf[myId] ?? 'Du',
          awayId: oppId,
          awayName: oppName,
        );
    final roundFx = [
      for (final f in all ?? const <Fixture>[])
        if (f.round == round) f
    ];
    final live = roundIsLive(roundFx, DateTime.now());
    final allFinished = roundFx.isNotEmpty &&
        roundFx.every((f) => f.status == FixtureStatus.finished);
    final started = live || allFinished;

    // Bye: eigener Spieltag spielfrei.
    if (pairing.isBye) {
      return MatchupBanner(
        round: round,
        homeName: nameOf[myId] ?? 'Du',
        awayName: null,
        homePoints: 0,
        awayPoints: 0,
        homeMe: true,
        awayMe: false,
        live: live,
        started: started,
        mine: true,
        onTap: () => openDetail(null, null),
      );
    }

    final oppId = pairing.home == myId ? pairing.away! : pairing.home;
    final totals = effectiveTotalsForRound(
      stats: ref.watch(roundStatsProvider(round)).valueOrNull ?? const {},
      round: round,
      managers: managers,
      roster: roster,
      playerById: {for (final p in pool) p.id: p},
      lineups: lineups,
      scoring: league.scoring,
      rosterConfig: league.roster,
    );
    final myPts = totals[myId] ?? 0.0;
    final oppPts = totals[oppId] ?? 0.0;
    return MatchupBanner(
      round: round,
      homeName: nameOf[myId] ?? 'Du',
      awayName: nameOf[oppId] ?? '?',
      homePoints: myPts,
      awayPoints: oppPts,
      homeMe: true,
      awayMe: false,
      live: live,
      started: started,
      mine: true,
      onTap: () => openDetail(oppId, nameOf[oppId]),
    );
  }
}

/// Ein MatchUp-Banner für eine **beliebige** Paarung (Heim vs. Gast) — die
/// Präsentation von [MatchupHero], aber mit explizit übergebenen Daten. Für
/// das Karussell im MatchUp-Tab. [mine] = eigene Paarung (zeigt „Du"/„Gegner");
/// [awayName] == null ⇒ spielfrei (Bye).
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
    required this.live,
    required this.started,
    required this.onTap,
    this.mine = false,
    this.homeSub,
    this.awaySub,
  });

  final int round;
  final String homeName;
  final String? awayName;
  final double homePoints;
  final double awayPoints;
  final bool homeMe;
  final bool awayMe;
  final bool live;
  final bool started;
  final bool mine;
  final VoidCallback onTap;

  /// Optionale dritte Zeile je Seite (Saison-Kontext, z. B. „Platz 3 · 5-2-1").
  final String? homeSub;
  final String? awaySub;

  @override
  Widget build(BuildContext context) {
    final accent = live ? _cRed : _cGreen;
    final status = live ? 'LIVE' : (started ? 'Beendet' : 'Vorschau');

    if (awayName == null) {
      return HeroShell(
        accent: accent,
        round: round,
        status: status,
        live: live,
        started: started,
        onTap: onTap,
        child: Row(
          children: [
            HeroAvatar(name: homeName, accent: accent),
            const SizedBox(width: 10),
            Expanded(
              child: HeroTeam(
                  name: homeName,
                  me: homeMe,
                  showRole: mine,
                  align: CrossAxisAlignment.start),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('spielfrei',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.bold)),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      );
    }

    final homeWin = started && homePoints > awayPoints;
    final awayWin = started && awayPoints > homePoints;
    return HeroShell(
      accent: accent,
      round: round,
      status: status,
      live: live,
      started: started,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              HeroAvatar(
                  name: homeName, accent: accent, dim: started && !homeWin),
              const SizedBox(width: 10),
              Expanded(
                child: HeroTeam(
                    name: homeName,
                    me: homeMe,
                    win: homeWin,
                    started: started,
                    live: live,
                    accent: accent,
                    showRole: mine,
                    subline: homeSub,
                    align: CrossAxisAlignment.start),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: HeroTeam(
                    name: awayName!,
                    me: awayMe,
                    win: awayWin,
                    started: started,
                    live: live,
                    accent: accent,
                    showRole: mine,
                    subline: awaySub,
                    align: CrossAxisAlignment.end),
              ),
              const SizedBox(width: 10),
              // Gegner in Rot → „vs"-Kontrast.
              HeroAvatar(
                  name: awayName!, accent: _cRed, dim: started && !awayWin),
            ],
          ),
          const SizedBox(height: 10),
          // **Der Punktestand steht mittig auf eigener Zeile, nicht zwischen
          // den Namen.** Dort nahm er genau die Breite weg, die die Namen
          // brauchen: „lennartruepke" schrumpfte auf Winzgröße, und aus
          // „FÜHRT" wurde „F…". Jetzt bekommt jede Seite die halbe Kastenbreite
          // und die Namen stehen in voller Größe.
          Center(
            child: ScoreBadge(
              left: homePoints,
              right: awayPoints,
              leftWin: homeWin,
              rightWin: awayWin,
              accent: accent,
            ),
          ),
          const SizedBox(height: 10),
          // „Momentum": Punkteanteil beider Seiten (vor Anpfiff 50/50) mit
          // Label je nach Status — füllt den Banner und gibt Kontext.
          _MomentumBar(left: homePoints, right: awayPoints),
          const SizedBox(height: 5),
          // Nur noch die Beschriftung. Links und rechts standen hier dieselben
          // zwei Zahlen, die zwei Zeilen darüber schon groß im Punktestand
          // stehen — dreimal dieselbe Auskunft in einem Kasten, der ohnehin zu
          // voll war.
          Center(
            child: Text(
                (live ? 'Live-Punkte' : (started ? 'Endpunkte' : 'Punkteanteil'))
                    .toUpperCase(),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }
}

/// Gemeinsamer Rahmen des MatchUp-Kopfs (Farbverlauf, Kopfzeile mit Spieltag
/// und Status-Pille, Marken-Wasserzeichen, Tap → Detail).
class HeroShell extends StatelessWidget {
  const HeroShell({
    super.key,
    required this.accent,
    required this.round,
    required this.status,
    required this.live,
    required this.started,
    required this.onTap,
    required this.child,
  });

  final Color accent;
  final int round;
  final String status;
  final bool live;

  /// Ist der Spieltag angepfiffen? Steuert, wie viel Farbe der Kasten trägt.
  final bool started;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grund = Theme.of(context).cardColor;
    // **Farbe nur, wo etwas ansteht.** Vorher füllte der Akzent die ganze
    // Fläche — auch vor dem Anpfiff, wo nichts läuft. Grün heißt in dieser App
    // „hier läuft etwas"; ein grüner Kasten für einen Spieltag, der erst
    // Samstag beginnt, sagt das Falsche. Jetzt trägt der Kasten den Kartengrund
    // und nur einen Hauch aus der Ecke: kräftig, solange live, leiser wenn
    // beendet, gar nicht davor. Dasselbe Muster wie bei den Ligakarten auf dem
    // Startbildschirm (`_kartenFlaeche`).
    final hauch = live
        ? accent.withValues(alpha: 0.22)
        : started
            ? accent.withValues(alpha: 0.10)
            : null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: grund,
            gradient: hauch == null
                ? null
                : LinearGradient(
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
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt, size: 16, color: accent),
                          const SizedBox(width: 4),
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(
                                  text: 'MATCHUP',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.5)),
                              TextSpan(
                                  text: '  ·  SPIELTAG $round',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1)),
                            ]),
                          ),
                          const Spacer(),
                          HeroStatusPill(
                              accent: accent, label: status, live: live),
                        ],
                      ),
                      child,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HeroStatusPill extends StatelessWidget {
  const HeroStatusPill(
      {super.key, required this.accent, required this.label, required this.live});

  final Color accent;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: live ? accent : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class HeroTeam extends StatelessWidget {
  const HeroTeam({
    super.key,
    required this.name,
    required this.me,
    required this.align,
    this.win = false,
    this.started = false,
    this.live = false,
    this.accent = Colors.white,
    this.showRole = true,
    this.subline,
  });

  final String name;
  final bool me;
  final bool win;

  /// „Du"/„Gegner" unter dem Namen zeigen (nur sinnvoll bei der eigenen
  /// Paarung; bei fremden Paarungen im Karussell ausgeschaltet).
  final bool showRole;

  /// Dritte Zeile (z. B. „Platz 3 · 5-2-1") — Saison-Kontext, optional.
  final String? subline;

  /// Ist der Spieltag schon angepfiffen (dann Sieg-/Führt-Hinweis statt Rolle)?
  final bool started;

  /// Läuft der Spieltag noch (dann „Führt", sonst „Sieg")?
  final bool live;

  /// Banner-Akzent (grün, bzw. rot solange live) für den Sieger-Hinweis.
  final Color accent;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final end = align == CrossAxisAlignment.end;
    final leads = started && win;
    return Column(
      crossAxisAlignment: align,
      children: [
        // **Der Name schrumpft, er wird nicht gekappt.** Dieselbe Regel wie
        // auf der Ergebnistafel im Live-Tab: Der Verein bzw. Manager *ist* der
        // Inhalt, und „lennartr…" ist keiner. Vorher fraß der Punktestand in
        // der Mitte die Seiten auf — bei „92 : 78,5" blieb links „SF…" stehen,
        // obwohl der Name fünf Zeichen hat.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            name,
            maxLines: 1,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: TextStyle(
                color: started && !win
                    ? Colors.white.withValues(alpha: 0.72)
                    : Colors.white,
                fontSize: 18,
                letterSpacing: 0.2,
                fontWeight: win || me ? FontWeight.w800 : FontWeight.w600),
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leads) ...[
              Icon(live ? Icons.arrow_drop_up : Icons.emoji_events,
                  size: live ? 16 : 13, color: _cGreen),
              const SizedBox(width: 1),
              // Beide Beschriftungen müssen schrumpfen können: Die Seite
              // bekommt nur, was Avatare und Punktestand übrig lassen, und bei
              // „92 : 78,5" ist das wenig. Ohne Flexible lief die Zeile über
              // (gemessen: 14 px) — auf dem Gerät der schwarz-gelbe Balken.
              Flexible(
                child: Text(live ? 'FÜHRT' : 'SIEG',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _cGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
              ),
            ] else if (showRole)
              Flexible(
                child: Text((me ? 'Du' : 'Gegner').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4)),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
        if (subline != null) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment:
                end ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Icon(Icons.leaderboard_outlined,
                  size: 11, color: Colors.white.withValues(alpha: 0.55)),
              const SizedBox(width: 3),
              Flexible(
                child: Text(subline!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Ergebnis-Feld in der Banner-Mitte: immer die beiden Punktzahlen als
/// Scoreboard (vor Anpfiff 0:0). Ein leicht abgedunkelter, gerundeter Chip
/// hebt das Ergebnis vom Marken-Logo dahinter ab; die Siegerzahl wird im
/// Akzent hervorgehoben, die des Verlierers gedimmt.
class ScoreBadge extends StatelessWidget {
  const ScoreBadge({
    super.key,
    required this.left,
    required this.right,
    required this.leftWin,
    required this.rightWin,
    required this.accent,
  });

  final double left;
  final double right;
  final bool leftWin;
  final bool rightWin;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Führender grün, Zurückliegender rot; bei Gleichstand/vor Anpfiff weiß.
    Color numColor(bool win, bool otherWin) => win
        ? _cGreen
        : (otherWin ? _cRed : Colors.white);
    Widget number(double v, bool win, bool otherWin) =>
        Text(formatPoints(v),
        style: TextStyle(
            color: numColor(win, otherWin),
            fontSize: 32,
            height: 1,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w900));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          number(left, leftWin, rightWin),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(':',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ),
          number(right, rightWin, leftWin),
        ],
      ),
    );
  }
}

/// Runder Manager-Avatar mit Initiale. Farbiger Ring im Banner-Akzent; der
/// Verlierer/Nicht-Führende wird gedimmt.
class HeroAvatar extends StatelessWidget {
  const HeroAvatar(
      {super.key, required this.name, required this.accent, this.dim = false});

  final String name;
  final Color accent;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: dim ? 0.10 : 0.26),
            Colors.white.withValues(alpha: dim ? 0.04 : 0.10),
          ],
        ),
        border: Border.all(
            color: dim ? Colors.white.withValues(alpha: 0.28) : accent,
            width: 2.5),
        boxShadow: dim
            ? null
            : [
                BoxShadow(
                    color: accent.withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: -3),
              ],
      ),
      child: Text(initial,
          style: TextStyle(
              color: Colors.white.withValues(alpha: dim ? 0.7 : 1),
              fontWeight: FontWeight.w900,
              fontSize: 19)),
    );
  }
}

/// „Momentum"-Balken: zeigt den Punkteanteil beider Seiten als Tauziehen —
/// meine Seite hell, der Gegner gedimmt. Rein visuell (kein Tap).
class _MomentumBar extends StatelessWidget {
  const _MomentumBar({required this.left, required this.right});

  final double left;
  final double right;

  /// Unentschieden und vor dem Anpfiff: **keine** Seite bekommt eine Wertung.
  /// Vorher stand hier grün gegen rot, auch bei 0:0 — das behauptete einen
  /// Führenden, den es nicht gab.
  static const _neutral = Color(0xFF9AA0AA);

  @override
  Widget build(BuildContext context) {
    // Flex nie 0 (sonst kollabiert die Seite komplett); min. schmaler Rest.
    // Flex verlangt ganze Zahlen; die Dezimalpunkte der Wertung sind für
    // die Balkenbreite ohne Belang.
    final l = left < 1 ? 1 : left.round();
    final r = right < 1 ? 1 : right.round();

    // **Grün heißt „führt", nicht „Heim".** Vorher trug die linke Seite den
    // Banner-Akzent — und der ist solange live rot, genau wie die rechte
    // Seite. Im laufenden Spieltag, also dann, wenn man am genauesten
    // hinsieht, waren beide Hälften rot und die Grenze verschwand.
    final linksVorn = left > right;
    final rechtsVorn = right > left;
    final linksFarbe =
        linksVorn ? _cGreen : (rechtsVorn ? _cRed : _neutral);
    final rechtsFarbe =
        rechtsVorn ? _cGreen : (linksVorn ? _cRed : _neutral);

    return Row(
      children: [
        Expanded(
          flex: l,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                linksFarbe.withValues(alpha: 0.95),
                linksFarbe.withValues(alpha: 0.7),
              ]),
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(4), right: Radius.circular(1)),
            ),
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          flex: r,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                rechtsFarbe.withValues(alpha: 0.7),
                rechtsFarbe.withValues(alpha: 0.95),
              ]),
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(1), right: Radius.circular(4)),
            ),
          ),
        ),
      ],
    );
  }
}
