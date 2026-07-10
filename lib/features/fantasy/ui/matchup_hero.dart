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
              child: Opacity(
                opacity: 0.45,
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      _watermarkGray, BlendMode.srcIn),
                  child: MatchUpChevron(size: 240),
                ),
              ),
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

    final accent = live ? _cRed : _cGreen;

    // Bye: eigener Spieltag spielfrei.
    if (pairing.isBye) {
      return HeroShell(
        accent: accent,
        round: round,
        status: live ? 'LIVE' : (allFinished ? 'Beendet' : 'Vorschau'),
        live: live,
        onTap: () => openDetail(null, null),
        child: Row(
          children: [
            HeroAvatar(name: nameOf[myId] ?? 'Du', accent: accent),
            const SizedBox(width: 10),
            Expanded(
              child: HeroTeam(
                  name: nameOf[myId] ?? 'Du',
                  me: true,
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
    final myWin = started && myPts > oppPts;
    final oppWin = started && oppPts > myPts;

    return HeroShell(
      accent: accent,
      round: round,
      status: live ? 'LIVE' : (allFinished ? 'Beendet' : 'Vorschau'),
      live: live,
      onTap: () => openDetail(oppId, nameOf[oppId]),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              HeroAvatar(
                  name: nameOf[myId] ?? 'Du',
                  accent: accent,
                  dim: started && !myWin),
              const SizedBox(width: 10),
              Expanded(
                child: HeroTeam(
                    name: nameOf[myId] ?? 'Du',
                    me: true,
                    win: myWin,
                    started: started,
                    live: live,
                    accent: accent,
                    align: CrossAxisAlignment.start),
              ),
              ScoreBadge(
                left: myPts,
                right: oppPts,
                leftWin: myWin,
                rightWin: oppWin,
                accent: accent,
              ),
              Expanded(
                child: HeroTeam(
                    name: nameOf[oppId] ?? '?',
                    me: false,
                    win: oppWin,
                    started: started,
                    live: live,
                    accent: accent,
                    align: CrossAxisAlignment.end),
              ),
              const SizedBox(width: 10),
              HeroAvatar(
                  name: nameOf[oppId] ?? '?',
                  accent: accent,
                  dim: started && !oppWin),
            ],
          ),
          if (started) ...[
            const SizedBox(height: 14),
            _MomentumBar(left: myPts, right: oppPts),
          ],
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
              colors: [accent.withValues(alpha: 0.42), _cBase],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
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
                          Text('MatchUp · Spieltag $round',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                      fontWeight: FontWeight.bold)),
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
  });

  final String name;
  final bool me;
  final bool win;

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
                  size: live ? 16 : 13, color: accent),
              const SizedBox(width: 1),
              Text(live ? 'Führt' : 'Sieg',
                  style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ] else
              Text(me ? 'Du' : 'Gegner',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11)),
          ],
        ),
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
    Color numColor(bool win, bool otherWin) => win
        ? accent
        : (otherWin ? Colors.white.withValues(alpha: 0.55) : Colors.white);
    Widget number(int v, bool win, bool otherWin) => Text('$v',
        style: TextStyle(
            color: numColor(win, otherWin),
            fontSize: 28,
            height: 1,
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
