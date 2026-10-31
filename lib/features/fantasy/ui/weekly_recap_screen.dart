import '../../../app/farben.dart';
import 'package:flutter/material.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/punktzahl.dart';
import '../../../app/widgets/skelett.dart';

import '../../../app/widgets/karte.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/weekly_recap.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
import 'manager_profile_screen.dart';
import 'matchday_stepper.dart';
import 'player_profile_sheet.dart';
import '../logic/kader_am.dart';
import '../models/roster_move.dart';

// Award-Palette (abgestimmt auf die MatchUp-Übersicht).

/// Öffnet das Wochen-Recap einer Liga (optional für einen bestimmten Spieltag).
void showWeeklyRecap(
  BuildContext context, {
  required FantasyLeague league,
  int? round,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WeeklyRecapScreen(league: league, initialRound: round),
    ),
  );
}

/// Stabile Manager-Reihenfolge wie im MatchUp-Tab (Draft-Position, dann ID).
List<String> stableManagerIds(List<FantasyManager> managers) {
  final ids = managers.map((m) => m.userId).toList();
  final posOf = {
    for (final m in managers) m.userId: m.draftPosition ?? 1 << 30,
  };
  ids.sort((a, b) {
    final pa = posOf[a]!;
    final pb = posOf[b]!;
    return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
  });
  return ids;
}

/// Wochen-Recap-Screen: pro Spieltag die „Sleeper-Awards" (Team der Woche,
/// MVP, Bank-Held, Nervenkrimi, Klatsche, vergeigte Bank, Griff ins Klo).
/// Standard-Spieltag ist der aktuelle; über den Stepper navigierbar.
class WeeklyRecapScreen extends ConsumerStatefulWidget {
  const WeeklyRecapScreen({super.key, required this.league, this.initialRound});

  final FantasyLeague league;
  final int? initialRound;

  @override
  ConsumerState<WeeklyRecapScreen> createState() => _WeeklyRecapScreenState();
}

class _WeeklyRecapScreenState extends ConsumerState<WeeklyRecapScreen> {
  int? _round;

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    // Beim Öffnen der zuletzt abgepfiffene Spieltag — der, über den es etwas
    // zu berichten gibt. Zurückblättern geht danach frei.
    final veroeffentlicht = ref.watch(veroeffentlichteRueckblickeProvider);
    final current =
        ref.watch(fantasyRecapRundeProvider).valueOrNull ??
        (veroeffentlicht.isEmpty ? null : veroeffentlicht.last) ??
        ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? widget.initialRound ?? current ?? 1;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final statsAsync = ref.watch(roundStatsProvider(round));
    final stats = statsAsync.valueOrNull ?? const <String, PlayerMatchStats>{};
    final clubIcons =
        ref.watch(clubIconsProvider).valueOrNull ?? const <String, String?>{};
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final bewegungen =
        ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
        const <RosterMove>[];
    final myId = ref.watch(currentUserProvider)?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Wochenrückblick')),
      // Nur wenn nichts dasteht — ein Nachladen darf den Rückblick nicht
      // gegen einen leeren Kreis tauschen.
      body: (managersAsync.valueOrNull == null || poolAsync.valueOrNull == null)
          ? const Skelett()
          : Builder(
              builder: (context) {
                final managers = managersAsync.requireValue;
                final pool = poolAsync.requireValue;
                final playerById = {for (final p in pool) p.id: p};
                final nameOf = {for (final m in managers) m.userId: m.display};
                final ids = stableManagerIds(managers);

                final roundFx = [
                  for (final f in allFx)
                    if (f.round == round) f,
                ];
                final freigegeben = veroeffentlicht.contains(round);

                // **Der Kader von damals, nicht der von heute.** Nach dem
                // Abpfiff schneidet der Rückblick ab: Wer später geholt wurde,
                // stand an diesem Spieltag nicht im Kader, und seine Punkte
                // gehören nicht auf diese Bank. („SFV03 hatte keine 230 Punkte
                // auf der Bank.")
                final abpfiff = abpfiffDerRunde(roundFx.map((f) => f.kickoff));
                final kader = abpfiff == null
                    ? roster
                    : kaderAm(
                        aktuell: roster,
                        bewegungen: bewegungen,
                        stichtag: abpfiff,
                      );

                final recap = computeWeeklyRecap(
                  round: round,
                  ids: ids,
                  roster: kader,
                  playerById: playerById,
                  lineups: lineups,
                  stats: stats,
                  scoring: league.scoring,
                  rosterConfig: league.roster,
                  remisGrenze: league.remisGrenze ?? 0,
                );

                void openManager(String id) => showManagerProfile(
                  context,
                  league: league,
                  managerId: id,
                  managerName: nameOf[id] ?? '?',
                );
                void openPlayer(String playerId, bool mine) {
                  final p = playerById[playerId];
                  if (p == null) return;
                  showPlayerProfile(
                    context,
                    league: league,
                    player: p,
                    clubIcon: clubIcons[p.club],
                    isMine: mine,
                  );
                }

                return ListView(
                  children: [
                    MatchdayStepper(
                      round: round,
                      onChanged: (r) => setState(() => _round = r),
                    ),
                    if (statsAsync.isLoading)
                      const LinearProgressIndicator(minHeight: 2),
                    if (ids.length < 2)
                      const _EmptyHint(
                        'Ein Rückblick braucht mindestens zwei Manager.',
                      )
                    // **Erst mit dem Wechsel auf den nächsten Spieltag**
                    // (19.10.2026) — vorher steht hier nur, wann er kommt.
                    else if (!freigegeben)
                      _EmptyHint(
                        'Der Rückblick auf Spieltag $round erscheint mit dem '
                        'Wechsel auf Spieltag ${round + 1}.',
                      )
                    else if (!recap.hasData)
                      const _EmptyHint(
                        'Für diesen Spieltag liegen keine gewerteten Punkte '
                        'vor.',
                      )
                    else
                      ..._awards(
                        context,
                        recap: recap,
                        nameOf: nameOf,
                        playerById: playerById,
                        clubIcons: clubIcons,
                        myId: myId,
                        onManager: openManager,
                        onPlayer: openPlayer,
                      ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
    );
  }

  /// **Team der Woche als Kopf, der Rest als eine Zeilengruppe**
  /// (19.10.2026, auf Ansage: „an unsere neuen, cleaneren Designs anpassen").
  /// Vorher sechs Karten untereinander, jede mit eigener Farbe für Symbol,
  /// Marke und Zahl. Jetzt trägt nur der Kopf Gold; die Zeilen stehen grau
  /// mit Umriss-Symbol, die Zahl weiß rechts. Wer selbst vorkommt, steht grün
  /// (Grün heißt „ich").
  List<Widget> _awards(
    BuildContext context, {
    required WeeklyRecap recap,
    required Map<String, String> nameOf,
    required Map<String, FantasyPlayer> playerById,
    required Map<String, String?> clubIcons,
    required String? myId,
    required void Function(String) onManager,
    required void Function(String, bool) onPlayer,
  }) {
    String name(String id) => nameOf[id] ?? '?';
    final zeilen = <Widget>[];

    void zeile({
      required IconData icon,
      required String titel,
      required String wer,
      String? unter,
      required String wert,
      bool pkt = true,
      bool ich = false,
      Widget? wappen,
      bool spieler = false,
      required VoidCallback onTap,
    }) {
      zeilen.add(
        _AwardZeile(
          icon: icon,
          titel: titel,
          wer: wer,
          spieler: spieler,
          unter: unter,
          wert: wert,
          pkt: pkt,
          ich: ich,
          wappen: wappen,
          onTap: onTap,
        ),
      );
    }

    void spieler(IconData icon, String titel, PlayerAward a) {
      final p = playerById[a.playerId];
      zeile(
        icon: icon,
        titel: titel,
        wer: p?.name ?? '?',
        spieler: p != null,
        unter: 'Kader: ${name(a.managerId)}',
        wert: formatPoints(a.points),
        ich: a.managerId == myId,
        wappen: p == null
            ? null
            : ClubBadge(club: p.club, iconUrl: clubIcons[p.club], size: 26),
        onTap: () => onPlayer(a.playerId, a.managerId == myId),
      );
    }

    if (recap.mvp != null) {
      spieler(Icons.star_outline, 'MVP der Woche', recap.mvp!);
    }
    if (recap.benchHero != null) {
      spieler(Icons.event_seat_outlined, 'Bank-Held', recap.benchHero!);
    }
    if (recap.closestWin != null) {
      final m = recap.closestWin!;
      zeile(
        icon: Icons.bolt_outlined,
        titel: 'Nervenkrimi',
        wer: name(m.winnerId),
        unter: 'schlägt ${name(m.loserId)} · +${formatPoints(m.margin)}',
        wert: '${formatPoints(m.winnerPoints)}:${formatPoints(m.loserPoints)}',
        pkt: false,
        ich: m.winnerId == myId || m.loserId == myId,
        onTap: () => onManager(m.winnerId),
      );
    }
    if (recap.blowout != null &&
        recap.blowout!.margin != recap.closestWin?.margin) {
      final m = recap.blowout!;
      zeile(
        icon: Icons.local_fire_department_outlined,
        titel: 'Klatsche',
        wer: name(m.winnerId),
        unter: 'deklassiert ${name(m.loserId)} · +${formatPoints(m.margin)}',
        wert: '${formatPoints(m.winnerPoints)}:${formatPoints(m.loserPoints)}',
        pkt: false,
        ich: m.winnerId == myId || m.loserId == myId,
        onTap: () => onManager(m.winnerId),
      );
    }
    if (recap.benchBlunder != null) {
      final b = recap.benchBlunder!;
      zeile(
        icon: Icons.sentiment_dissatisfied_outlined,
        titel: 'Vergeigte Bank',
        wer: name(b.managerId),
        unter: 'auf der Bank liegengelassen',
        wert: formatPoints(b.pointsLeft),
        ich: b.managerId == myId,
        onTap: () => onManager(b.managerId),
      );
    }
    if (recap.lowScore != null) {
      final l = recap.lowScore!;
      zeile(
        icon: Icons.trending_down_outlined,
        titel: 'Griff ins Klo',
        wer: name(l.managerId),
        unter: 'niedrigstes Ergebnis',
        wert: formatPoints(l.points),
        ich: l.managerId == myId,
        onTap: () => onManager(l.managerId),
      );
    }

    final top = recap.topScore;
    return [
      if (top != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _TeamDerWoche(
            name: name(top.managerId),
            punkte: top.points,
            ich: top.managerId == myId,
            onTap: () => onManager(top.managerId),
          ),
        ),
      if (zeilen.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Kapitelmarke('Auszeichnungen'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            decoration: kartenDeko(context),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, z) in zeilen.indexed) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 52,
                      color: Theme.of(context).dividerColor,
                    ),
                  z,
                ],
              ],
            ),
          ),
        ),
      ],
    ];
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Der Kopf des Rückblicks: Team der Woche, groß, schräg, mit der Zahl.
class _TeamDerWoche extends StatelessWidget {
  const _TeamDerWoche({
    required this.name,
    required this.punkte,
    required this.ich,
    required this.onTap,
  });

  final String name;
  final double punkte;
  final bool ich;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    return Karte(
      hauch: context.farben.gold,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TEAM DER WOCHE',
                  style: TextStyle(
                    color: context.farben.gold,
                    fontSize: Schrift.label,
                    fontWeight: Schrift.ueberschriftGewicht,
                    fontStyle: Schrift.ueberschriftStil,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    name.toUpperCase(),
                    style: TextStyle(
                      fontSize: Schrift.gross,
                      fontWeight: Schrift.ueberschriftGewicht,
                      fontStyle: Schrift.ueberschriftStil,
                      color: ich ? context.farben.gruen : null,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'höchstes Ergebnis des Spieltags',
                  style: TextStyle(fontSize: Schrift.label, color: grau),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Punktzahl(
                punkte,
                stil: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                'Pkt',
                style: TextStyle(fontSize: Schrift.label, color: grau),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Eine Auszeichnung als Zeile: Umriss-Symbol, Marke, Träger, Zahl rechts.
class _AwardZeile extends StatelessWidget {
  const _AwardZeile({
    required this.icon,
    required this.titel,
    required this.wer,
    required this.unter,
    required this.wert,
    required this.pkt,
    required this.ich,
    required this.wappen,
    required this.onTap,
    this.spieler = false,
  });

  final IconData icon;
  final String titel;
  final String wer;

  /// Ein Spielername steht in Versalien und kursiv (31.10.2026), ein
  /// Managername nicht.
  final bool spieler;
  final String? unter;
  final String wert;
  final bool pkt;
  final bool ich;
  final Widget? wappen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: grau),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titel.toUpperCase(),
                    style: TextStyle(
                      fontSize: Schrift.mikro,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: grau,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    spieler ? wer.toUpperCase() : wer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Schrift.text,
                      fontWeight: spieler
                          ? Schrift.ueberschriftGewicht
                          : FontWeight.w700,
                      fontStyle: spieler ? Schrift.ueberschriftStil : null,
                      color: ich ? context.farben.gruen : null,
                    ),
                  ),
                  if (unter != null)
                    Text(
                      unter!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Schrift.label, color: grau),
                    ),
                ],
              ),
            ),
            if (wappen != null) ...[const SizedBox(width: 8), wappen!],
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  wert,
                  style: const TextStyle(
                    fontSize: Schrift.titel,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (pkt)
                  Text(
                    'Pkt',
                    style: TextStyle(fontSize: Schrift.label, color: grau),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kompakte Recap-Kachel: zeigt Team der Woche + MVP eines Spieltags und
/// öffnet auf Tippen das volle Recap.
///
/// **Erst nach dem Abpfiff des letzten Spiels.** Ein Recap ist eine Bilanz —
/// „Team der Woche" mitten im Spieltag benennt den, der zufällig schon
/// gespielt hat, und ändert sich mit jedem Anpfiff wieder. Ohne [runde] nimmt
/// die Kachel den aktuellen Spieltag; die Tabelle reicht dagegen einen
/// **ausgewählten** durch, damit man zurückblättern kann.
class WeeklyRecapCard extends ConsumerWidget {
  const WeeklyRecapCard({super.key, required this.league, this.runde});

  final FantasyLeague league;

  /// Fester Spieltag; `null` = der zuletzt abgepfiffene.
  final int? runde;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **Nicht der aktuelle Spieltag, sondern der zurückliegende.** Der
    // aktuelle springt montags um 15:00 weiter; ein Rückblick auf einen
    // Spieltag, der noch gar nicht gespielt ist, wäre leer. Der Rückblick
    // bleibt bis zum Anstoß des nächsten stehen.
    final current = runde ?? ref.watch(fantasyRecapRundeProvider).valueOrNull;
    if (current == null) return const SizedBox.shrink();
    // **Erst mit dem Wechsel auf den nächsten Spieltag** (19.10.2026):
    // dieselbe Frist, zu der der Server den Push schickt.
    if (!ref.watch(veroeffentlichteRueckblickeProvider).contains(current)) {
      return const SizedBox.shrink();
    }

    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    if (managers == null || pool == null || managers.length < 2) {
      return const SizedBox.shrink();
    }
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final stats =
        ref.watch(roundStatsProvider(current)).valueOrNull ??
        const <String, PlayerMatchStats>{};

    final playerById = {for (final p in pool) p.id: p};
    final nameOf = {for (final m in managers) m.userId: m.display};
    // Derselbe Schnitt wie im vollen Rückblick: der Kader zum Abpfiff.
    final abpfiff = abpfiffDerRunde([
      for (final f
          in ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
              const <Fixture>[])
        if (f.round == current) f.kickoff,
    ]);
    final kader = abpfiff == null
        ? roster
        : kaderAm(
            aktuell: roster,
            bewegungen:
                ref.watch(rosterMovesProvider(league.id)).valueOrNull ??
                const <RosterMove>[],
            stichtag: abpfiff,
          );
    final recap = computeWeeklyRecap(
      round: current,
      ids: stableManagerIds(managers),
      roster: kader,
      playerById: playerById,
      lineups: lineups,
      stats: stats,
      scoring: league.scoring,
      rosterConfig: league.roster,
      remisGrenze: league.remisGrenze ?? 0,
    );
    if (!recap.hasData) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final top = recap.topScore;
    final mvp = recap.mvp;

    // **Dieselbe Hülle wie jede andere Karte.** Vorher lag sie auf einer
    // goldenen Fläche mit goldenem Rand — für einen Rückblick, bei dem nichts
    // zu tun ist. Das Gold trägt jetzt nur noch der Hauch aus der Ecke und
    // die Marke im Inhalt.
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Karte(
        hauch: context.farben.gold,
        radius: 18,
        padding: const EdgeInsets.all(16),
        onTap: () => showWeeklyRecap(context, league: league, round: current),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'RÜCKBLICK · SPIELTAG ${recap.round}',
                  style: TextStyle(
                    color: context.farben.gold,
                    fontSize: Schrift.label,
                    fontWeight: Schrift.ueberschriftGewicht,
                    fontStyle: Schrift.ueberschriftStil,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (top != null)
              _MiniLine(
                label: 'Team der Woche',
                value: nameOf[top.managerId] ?? '?',
                trailing: '${formatPoints(top.points)} Pkt',
              ),
            if (mvp != null) ...[
              const SizedBox(height: 4),
              _MiniLine(
                label: 'MVP',
                value: playerById[mvp.playerId]?.name ?? '?',
                spieler: true,
                trailing: '${formatPoints(mvp.points)} Pkt',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  const _MiniLine({
    required this.label,
    required this.value,
    required this.trailing,
    this.spieler = false,
  });

  final String label;
  final String value;
  final bool spieler;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: TextStyle(
              fontSize: Schrift.label,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            spieler ? value.toUpperCase() : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: Schrift.text,
              fontWeight: spieler
                  ? Schrift.ueberschriftGewicht
                  : FontWeight.w700,
              fontStyle: spieler ? Schrift.ueberschriftStil : null,
            ),
          ),
        ),
        Text(
          trailing,
          style: const TextStyle(
            fontSize: Schrift.text,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
