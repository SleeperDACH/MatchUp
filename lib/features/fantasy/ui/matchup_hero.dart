import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/matchup_chevron.dart';
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
const _cBase = Color(0xFF12141C);

// Einheitlicher Grauton fürs ausgegraute Banner-Wasserzeichen.
const _watermarkGray = Color(0xFF9AA0AA);

/// MatchUp-Chevron als Marken-Emblem mittig hinter dem Kopf-Banner: groß,
/// ausgegraut und dezent, der Text liegt deckend darüber. `BlendMode.srcIn`
/// überschreibt beide Markenfarben (grün|rot) mit **einem** Grauton, sodass
/// das Logo einheitlich grau erscheint. `BoxFit.contain` hält das
/// Seitenverhältnis; das ClipRRect des Banners beschneidet überstehende
/// Ränder. Nimmt keine Tap-Events entgegen.
Widget heroWatermark() => Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: FittedBox(
              fit: BoxFit.contain,
              // Direkt ausgegraut gezeichnet (Alpha in der Farbe) — spart die
              // teuren saveLayer von Opacity + ColorFiltered.
              child: MatchUpChevron(
                  size: 240,
                  color: _watermarkGray.withValues(alpha: 0.45)),
            ),
          ),
        ),
      ),
    );

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
    final myPts = totals[myId] ?? 0;
    final oppPts = totals[oppId] ?? 0;
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
  final int homePoints;
  final int awayPoints;
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
              ScoreBadge(
                left: homePoints,
                right: awayPoints,
                leftWin: homeWin,
                rightWin: awayWin,
                accent: accent,
              ),
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
              HeroAvatar(
                  name: awayName!, accent: accent, dim: started && !awayWin),
            ],
          ),
          const SizedBox(height: 12),
          // „Momentum": Punkteanteil beider Seiten (vor Anpfiff 50/50) mit
          // Label je nach Status — füllt den Banner und gibt Kontext.
          _MomentumBar(left: homePoints, right: awayPoints),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$homePoints',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
              Text(
                  (live
                          ? 'Live-Punkte'
                          : (started ? 'Endpunkte' : 'Punkteanteil'))
                      .toUpperCase(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5)),
              Text('$awayPoints',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ],
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
    required this.onTap,
    required this.child,
  });

  final Color accent;
  final int round;
  final String status;
  final bool live;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isGreen = accent == _cGreen;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 170),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // Der Grün-Banner soll klar nach dem MatchUp-Logo-Grün aussehen;
              // dafür startet er kräftiger und hält den Grünton länger.
              stops: isGreen ? const [0.0, 0.55, 1.0] : const [0.0, 1.0],
              colors: isGreen
                  ? [
                      accent.withValues(alpha: 0.78),
                      accent.withValues(alpha: 0.34),
                      _cBase,
                    ]
                  : [accent.withValues(alpha: 0.42), _cBase],
            ),
            border: Border.all(
                color: accent.withValues(alpha: isGreen ? 0.62 : 0.5)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                heroWatermark(),
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
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: TextStyle(
              color: started && !win
                  ? Colors.white.withValues(alpha: 0.72)
                  : Colors.white,
              fontSize: 18,
              letterSpacing: 0.2,
              fontWeight: win || me ? FontWeight.w800 : FontWeight.w600),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leads) ...[
              Icon(live ? Icons.arrow_drop_up : Icons.emoji_events,
                  size: live ? 16 : 13, color: _cGreen),
              const SizedBox(width: 1),
              Text(live ? 'FÜHRT' : 'SIEG',
                  style: const TextStyle(
                      color: _cGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2)),
            ] else if (showRole)
              Text((me ? 'Du' : 'Gegner').toUpperCase(),
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4))
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

  final int left;
  final int right;
  final bool leftWin;
  final bool rightWin;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Führender grün, Zurückliegender rot; bei Gleichstand/vor Anpfiff weiß.
    Color numColor(bool win, bool otherWin) => win
        ? _cGreen
        : (otherWin ? _cRed : Colors.white);
    Widget number(int v, bool win, bool otherWin) => Text('$v',
        style: TextStyle(
            color: numColor(win, otherWin),
            fontSize: 30,
            height: 1,
            letterSpacing: -0.5,
            fontWeight: FontWeight.w800));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
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
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: dim ? 0.06 : 0.16),
        border: Border.all(
            color: dim ? Colors.white.withValues(alpha: 0.28) : accent,
            width: 2),
      ),
      child: Text(initial,
          style: TextStyle(
              color: Colors.white.withValues(alpha: dim ? 0.7 : 1),
              fontWeight: FontWeight.w800,
              fontSize: 16)),
    );
  }
}

/// „Momentum"-Balken: zeigt den Punkteanteil beider Seiten als Tauziehen —
/// meine Seite hell, der Gegner gedimmt. Rein visuell (kein Tap).
class _MomentumBar extends StatelessWidget {
  const _MomentumBar({required this.left, required this.right});

  final int left;
  final int right;

  @override
  Widget build(BuildContext context) {
    // Flex nie 0 (sonst kollabiert die Seite komplett); min. schmaler Rest.
    final l = left < 1 ? 1 : left;
    final r = right < 1 ? 1 : right;
    return Row(
      children: [
        Expanded(
          flex: l,
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(4), right: Radius.circular(1)),
            ),
          ),
        ),
        const SizedBox(width: 3),
        Expanded(
          flex: r,
          child: Container(
            height: 7,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.26),
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(1), right: Radius.circular(4)),
            ),
          ),
        ),
      ],
    );
  }
}
