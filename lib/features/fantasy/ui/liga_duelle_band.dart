import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/punktzahl.dart';
import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/h2h_grundlage.dart';
import '../logic/saisonverlauf.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'fantasy_league_screen.dart' show LigaReiter;
import 'matchup_hero.dart';
import 'matchup_lineups.dart';
import 'matchups_screen.dart'
    show matchupKarussellSeiteProvider, matchupSprungProvider;

/// **Alle Duelle des Spieltags auf einen Blick** — oben im Tabellen-Reiter,
/// nach dem Vorbild Sleeper (auf Ansage, 16.10.2026).
///
/// Eine waagerecht wischbare Reihe kompakter Karten, die eigene vorn:
/// je Seite Bild, Name, Platz · Bilanz · Serie, groß der Stand (vor dem
/// Anpfiff die Prognose, gedämpft) und die Siegchance. Ein Tipp springt in den
/// MatchUp-Reiter, auf genau diese Paarung.
///
/// **Dieselben Zahlen wie im MatchUp-Tab**, nicht eine zweite Rechnung:
/// Paarungen aus `roundPairings` über `h2hGrundlage.ids`, Stände aus
/// `effectiveTotalsForRound`, Prognose und Chance aus `duellPrognose`,
/// Bilanz aus `bannerBilanz`, die Reihenfolge (eigene zuerst) wie im
/// Karussell — sonst führte der Tipp auf ein anderes Duell.
class LigaDuelleBand extends ConsumerWidget {
  const LigaDuelleBand({super.key, required this.league});

  final FantasyLeague league;

  static const kartenBreite = 252.0;
  static const kartenHoehe = 150.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managers =
        ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    final round = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    if (managers == null || pool == null || round == null) {
      return const SizedBox.shrink();
    }
    if (managers.length < 2) return const SizedBox.shrink();
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final weekStats =
        ref.watch(roundStatsProvider(round)).valueOrNull ?? const {};
    final seasonStats = ref.watch(seasonStatsProvider).valueOrNull ?? const {};
    final allFx = ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;
    final abgepfiffen = ref.watch(abgepfiffeneRundenProvider);
    final ausfaelle = ref.watch(absencesProvider).valueOrNull ?? const {};
    final wochenStreuung = ref.watch(fantasyWochenStreuungProvider(league.id));

    final playerById = {for (final p in pool) p.id: p};
    final byId = {for (final m in managers) m.userId: m};
    final grundlage = h2hGrundlage(
      league: league,
      managers: managers,
      roster: roster,
      lineups: lineups,
      playerById: playerById,
      seasonStats: seasonStats,
      abgepfiffen: abgepfiffen,
    );
    final fertig = gewerteteRunden(abgepfiffen, seasonStats.keys);
    final saisonGewertet = {
      for (final e in seasonStats.entries)
        if (fertig.contains(e.key)) e.key: e.value,
    };
    final totals = effectiveTotalsForRound(
      stats: weekStats,
      round: round,
      managers: managers,
      roster: roster,
      playerById: playerById,
      lineups: lineups,
      scoring: league.scoring,
      rosterConfig: league.roster,
    );

    final roundFx = [
      for (final f in allFx)
        if (f.round == round) f
    ];
    final jetzt = DateTime.now();
    final live = roundIsLive(roundFx, jetzt);
    final started = live ||
        (roundFx.isNotEmpty &&
            roundFx.every((f) => f.status == FixtureStatus.finished));
    final beendet = started && !live;

    final pairings = roundPairings(grundlage.ids, round);
    final mine = myId == null
        ? null
        : pairings.where((m) => m.home == myId || m.away == myId).firstOrNull;
    final ordered = <Matchup>[
      ?mine,
      for (final m in pairings)
        if (mine == null || !identical(m, mine)) m,
    ];

    MatchupSideData seite(String id) => computeSideData(
          league: league,
          round: round,
          managerId: id,
          byId: playerById,
          roster: roster,
          lineups: lineups,
          stats: weekStats,
        );

    final karten = <Widget>[];
    for (final (i, p) in ordered.indexed) {
      if (p.isBye) continue;
      // Wie im Karussell: Bei der eigenen Paarung stehe ich oben.
      final (hId, aId) = p.away == myId ? (p.away!, p.home) : (p.home, p.away!);
      final prognose = duellPrognose(
        round: round,
        heim: seite(hId),
        gast: seite(aId),
        spiele: allFx,
        saisonGewertet: saisonGewertet,
        regeln: league.scoring,
        ausfaelle: ausfaelle,
        wochenStreuung: wochenStreuung,
        jetzt: jetzt,
      );
      final chance = prognose.siegchanceHeim;
      _DuellSeite daten(String id, double? erwartet, double? c, double gegner) =>
          _DuellSeite(
            manager: byId[id],
            bilanz: bannerBilanz(grundlage, id),
            punkte: totals[id] ?? 0,
            gegnerPunkte: gegner,
            erwartet: erwartet,
            chance: c,
            ich: id == myId,
            remisGrenze: league.remisGrenze ?? 0,
          );
      karten.add(_DuellKarte(
        heim: daten(hId, prognose.heimErwartet, chance, totals[aId] ?? 0),
        gast: daten(aId, prognose.gastErwartet,
            chance == null ? null : 1 - chance, totals[hId] ?? 0),
        started: started,
        beendet: beendet,
        live: live,
        onTap: () {
          // Auf genau diese Paarung im MatchUp-Reiter: Seite merken, Sprung
          // auslösen (setzt den Spieltag zurück auf den aktuellen), Reiter
          // wechseln.
          ref.read(matchupKarussellSeiteProvider(league.id).notifier).state = i;
          ref.read(matchupSprungProvider(league.id).notifier).state++;
          DefaultTabController.maybeOf(context)?.animateTo(LigaReiter.matchup);
        },
      ));
    }
    if (karten.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: kartenHoehe,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: karten.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => karten[i],
      ),
    );
  }
}

class _DuellSeite {
  const _DuellSeite({
    required this.manager,
    required this.bilanz,
    required this.punkte,
    required this.gegnerPunkte,
    required this.erwartet,
    required this.chance,
    required this.ich,
    required this.remisGrenze,
  });

  final num remisGrenze;
  final FantasyManager? manager;
  final BannerBilanz bilanz;
  final double punkte;
  final double gegnerPunkte;
  final double? erwartet;
  final double? chance;
  final bool ich;
}

class _DuellKarte extends StatelessWidget {
  const _DuellKarte({
    required this.heim,
    required this.gast,
    required this.started,
    required this.beendet,
    required this.live,
    required this.onTap,
  });

  final _DuellSeite heim;
  final _DuellSeite gast;
  final bool started;
  final bool beendet;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meins = heim.ich || gast.ich;
    return SizedBox(
      width: LigaDuelleBand.kartenBreite,
      child: Karte(
        // Der Hauch gehört der Karte, in der du vorkommst — dieselbe Regel
        // wie bei den Duellen im Tippspiel und im Rückblick.
        hauch: meins ? scheme.primary : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Zeile(seite: heim, started: started, beendet: beendet, live: live),
            Row(
              children: [
                Expanded(
                    child: Divider(
                        height: 1,
                        color: scheme.onSurface.withValues(alpha: 0.08))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    live ? 'LIVE' : 'VS',
                    style: TextStyle(
                      fontSize: Schrift.label,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: live
                          ? MatchUpColors.red
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                    child: Divider(
                        height: 1,
                        color: scheme.onSurface.withValues(alpha: 0.08))),
              ],
            ),
            _Zeile(seite: gast, started: started, beendet: beendet, live: live),
          ],
        ),
      ),
    );
  }
}

/// Eine Seite der Karte: Bild, Name, Bilanz — rechts Stand und Chance.
class _Zeile extends StatelessWidget {
  const _Zeile({
    required this.seite,
    required this.started,
    required this.beendet,
    required this.live,
  });

  final _DuellSeite seite;
  final bool started;
  final bool beendet;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = seite.manager;
    final ausgang = duellErgebnis(seite.punkte, seite.gegnerPunkte,
        remisGrenze: seite.remisGrenze);
    final verloren = beendet && ausgang < 0;

    // Groß: der Stand, vor dem Anpfiff die Prognose gedämpft, sonst ein
    // Strich — dieselbe Regel wie im MatchUp-Kasten.
    final double? gross = started ? seite.punkte : seite.erwartet;
    final grossFarbe = !started
        ? scheme.onSurface.withValues(alpha: 0.55)
        : verloren
            ? scheme.onSurface.withValues(alpha: 0.6)
            : scheme.onSurface;

    // Klein darunter: Ausgang, Chance oder nichts.
    final String? klein;
    final Color kleinFarbe;
    if (beendet) {
      final sieg = ausgang > 0;
      klein = sieg ? 'SIEG' : (verloren ? 'NIEDERLAGE' : 'REMIS');
      kleinFarbe = sieg ? MatchUpColors.green : (verloren ? MatchUpColors.red : kChanceNeutral);
    } else if (seite.chance != null) {
      final prozent = (seite.chance! * 100).round().clamp(0, 100);
      klein = '$prozent % SIEG';
      kleinFarbe = chanceFarben(prozent.clamp(1, 99)).$1;
    } else {
      klein = null;
      kleinFarbe = scheme.onSurfaceVariant;
    }

    final serie = seite.bilanz.serie;
    final (pfeil, buchstabe, serieFarbe) = switch (serie?.ausgang) {
      DuellAusgang.sieg => ('▲', 'S', MatchUpColors.green),
      DuellAusgang.niederlage => ('▼', 'N', MatchUpColors.red),
      _ => ('■', 'U', kChanceNeutral),
    };

    return Row(
      children: [
        AppAvatar(
          imageUrl: m?.avatarUrl,
          emoji: m?.avatarEmoji,
          colorHex: m?.avatarColor,
          fallbackText: m?.display,
          size: 32,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  m?.display ?? '?',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: Schrift.text,
                    fontWeight: seite.ich ? FontWeight.w800 : FontWeight.w700,
                  ),
                ),
              ),
              if (seite.bilanz.zeile != null)
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: seite.bilanz.zeile),
                    if (serie != null) ...[
                      const TextSpan(text: ' · '),
                      TextSpan(
                        text: '$pfeil${serie.anzahl}$buchstabe',
                        style: TextStyle(
                            color: serieFarbe, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Schrift.label,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (gross == null)
              Text('–',
                  style: TextStyle(
                      fontSize: Schrift.titel,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant))
            else
              Punktzahl(
                gross,
                stil: TextStyle(
                  fontSize: Schrift.titel,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: grossFarbe,
                ),
              ),
            if (klein != null)
              Text(
                klein,
                style: TextStyle(
                  fontSize: Schrift.label,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: kleinFarbe,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
