import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../logic/h2h_grundlage.dart';
import '../logic/playoff.dart';
import '../logic/saisonverlauf.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'manager_profile_screen.dart';

/// Reiter „Saison" im Ligaprofil: die Ergebnisse der gespielten Duelle und
/// der Spielplan der kommenden.
///
/// **Ergebnisse oben, chronologisch; Spielplan darunter.** Wer ein Profil
/// öffnet, fragt zuerst „wie läuft es bei ihm?", und die Antwort darauf ist
/// die Bilanz samt den letzten Duellen. Der Spielplan ist die zweite Frage.
///
/// Gerechnet wird mit [h2hGrundlage] und [saisonverlauf] — **derselben**
/// Grundlage wie die Tabelle. Eine Bilanz, die im Profil anders aussieht als
/// in der Tabelle, wäre schlimmer als gar keine.
class ManagerSaisonTab extends ConsumerWidget {
  const ManagerSaisonTab({
    super.key,
    required this.league,
    required this.managerId,
  });

  final FantasyLeague league;
  final String managerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final pool = ref.watch(playerPoolProvider).valueOrNull;
    if (managers == null || pool == null) {
      return const Skelett();
    }
    final roster =
        ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups =
        ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final seasonStats =
        ref.watch(seasonStatsProvider).valueOrNull ??
        const <int, Map<String, PlayerMatchStats>>{};
    final fixtures =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ??
        const <Fixture>[];

    final grundlage = h2hGrundlage(
      league: league,
      managers: managers,
      roster: roster,
      lineups: lineups,
      playerById: {for (final p in pool) p.id: p},
      seasonStats: seasonStats,
      abgepfiffen: ref.watch(abgepfiffeneRundenProvider),
    );

    // Die reguläre Saison endet vor den Playoffs; dort paart das Bracket,
    // nicht der Round-Robin.
    final playoffStart = league.playoffTeams == null
        ? null
        : computePlayoffPlan(
            teams: league.playoffTeams!,
            weeksPerRound: league.playoffWeeks ?? 1,
            tradeDeadlineOffset: league.tradeDeadlineOffset ?? 5,
            totalTeams: managers.length,
          ).startRound;
    final letzteRunde = playoffStart == null
        ? kRegularSeasonMatchdays
        : playoffStart - 1;

    final verlauf = saisonverlauf(
      ids: grundlage.ids,
      managerId: managerId,
      gewertet: grundlage.summen,
      letzteRunde: letzteRunde,
      remisGrenze: grundlage.remis,
    );
    if (verlauf.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Für diesen Manager gibt es noch keinen Spielplan.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final byId = {for (final m in managers) m.userId: m};
    final standings = h2hStandings(grundlage.ids, grundlage.summen,
        remisGrenze: grundlage.remis);
    final platzIndex = standings.indexWhere((r) => r.managerId == managerId);
    final record = platzIndex < 0 ? null : standings[platzIndex];
    final nochNichtsGewertet = standings.every((r) => r.played == 0);

    // Anpfiff und Zustand je Spieltag, aus dem Bundesliga-Spielplan.
    final ersterAnpfiff = <int, DateTime>{};
    final laeuft = <int>{};
    final jetzt = DateTime.now();
    final proRunde = <int, List<Fixture>>{};
    for (final f in fixtures) {
      (proRunde[f.round] ??= []).add(f);
    }
    proRunde.forEach((runde, fx) {
      fx.sort((a, b) => a.kickoff.compareTo(b.kickoff));
      ersterAnpfiff[runde] = fx.first.kickoff;
      final begonnen = fx.any((f) => f.kickoff.isBefore(jetzt));
      final fertig = fx.every((f) => f.status == FixtureStatus.finished);
      if (begonnen && !fertig) laeuft.add(runde);
    });

    // Ein gewerteter Spieltag gehört zu den Ergebnissen, auch wenn der
    // Manager dort spielfrei war — sonst stünde ein vergangener Spieltag im
    // Spielplan.
    final ergebnisse = [
      for (final s in verlauf)
        if (grundlage.summen.containsKey(s.runde)) s,
    ];
    final kommend = [
      for (final s in verlauf)
        if (!grundlage.summen.containsKey(s.runde)) s,
    ];

    void oeffne(String? gegnerId) {
      if (gegnerId == null) return;
      final m = byId[gegnerId];
      showManagerProfile(
        context,
        league: league,
        managerId: gegnerId,
        managerName: m?.display ?? '?',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Abstand.m,
        Abstand.m,
        Abstand.m,
        Abstand.xl,
      ),
      children: [
        _Bilanz(
          record: nochNichtsGewertet ? null : record,
          platz: nochNichtsGewertet ? null : platzIndex + 1,
        ),
        const Kapitelmarke('Ergebnisse'),
        if (ergebnisse.isEmpty)
          _Leer(
            nochNichtsGewertet
                ? 'Noch kein Spieltag abgepfiffen.'
                : 'Noch kein Duell gewertet.',
          )
        else
          Karte(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ergebnisse.length; i++) ...[
                  if (i > 0) const _Trenner(),
                  _DuellZeile(
                    spiel: ergebnisse[i],
                    gegner: byId[ergebnisse[i].gegnerId],
                    onTap: ergebnisse[i].spielfrei
                        ? null
                        : () => oeffne(ergebnisse[i].gegnerId),
                  ),
                ],
              ],
            ),
          ),
        const Kapitelmarke('Spielplan'),
        if (kommend.isEmpty)
          const _Leer('Die reguläre Saison ist gespielt.')
        else
          Karte(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < kommend.length; i++) ...[
                  if (i > 0) const _Trenner(),
                  _DuellZeile(
                    spiel: kommend[i],
                    gegner: byId[kommend[i].gegnerId],
                    anpfiff: ersterAnpfiff[kommend[i].runde],
                    laeuft: laeuft.contains(kommend[i].runde),
                    onTap: kommend[i].spielfrei
                        ? null
                        : () => oeffne(kommend[i].gegnerId),
                  ),
                ],
              ],
            ),
          ),
        if (playoffStart != null && playoffStart <= kRegularSeasonMatchdays)
          Padding(
            padding: const EdgeInsets.only(top: Abstand.m),
            child: Text(
              'Ab Spieltag $playoffStart: Playoffs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Kopf des Reiters: Bilanz, Platz und erzielte Punkte in einer Leiste.
class _Bilanz extends StatelessWidget {
  const _Bilanz({
    required this.record,
    required this.platz,
  });

  final H2HRecord? record;
  final int? platz;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget zahl(String wert, String label) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              wert,
              maxLines: 1,
              style: TextStyle(
                fontSize: Schrift.titel,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: Schrift.label,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    Widget linie() =>
        Container(width: 1, height: 32, color: Theme.of(context).dividerColor);
    final r = record;
    // **Ohne Kasten** (Design-Ideen Punkt 1): Die Leiste ist Auskunft, kein
    // Tipp-Ziel — Karten tragen in dieser App nur, was man antippt.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Abstand.s),
      child: Row(
        children: [
          // Reihenfolge Sieg – Unentschieden – Niederlage, wie in der Tabelle.
          zahl(r == null ? '–' : '${r.wins}-${r.ties}-${r.losses}', 'S-U-N'),
          linie(),
          zahl(platz == null ? '–' : '$platz.', 'Platz'),
          linie(),
          zahl(r == null ? '–' : formatPoints(r.pointsFor), 'Punkte'),
          linie(),
          // Schnitt je Duell — spielfreie Spieltage zählen nicht mit, dieselbe
          // Rechnung wie die Ø-Spalte der Tabelle.
          zahl(
            r == null || r.played == 0
                ? '–'
                : formatPoints(r.pointsFor / r.played),
            'Ø Punkte',
          ),
        ],
      ),
    );
  }
}

/// Eine Zeile: Spieltag, Gegner, rechts Ergebnis bzw. Anpfiff.
class _DuellZeile extends StatelessWidget {
  const _DuellZeile({
    required this.spiel,
    required this.gegner,
    required this.onTap,
    this.anpfiff,
    this.laeuft = false,
  });

  final SaisonSpiel spiel;
  final FantasyManager? gegner;
  final VoidCallback? onTap;
  final DateTime? anpfiff;
  final bool laeuft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leise = scheme.onSurfaceVariant;
    final name = spiel.spielfrei ? 'spielfrei' : (gegner?.display ?? '?');

    Widget rechts;
    if (spiel.gewertet) {
      rechts = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${formatPoints(spiel.eigene!)} : ${formatPoints(spiel.gegner!)}',
            style: TextStyle(
              fontSize: Schrift.text,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: Abstand.s),
          _AusgangMarke(spiel.ausgang!),
        ],
      );
    } else if (laeuft) {
      rechts = Text(
        'läuft',
        style: TextStyle(
          fontSize: Schrift.label,
          fontWeight: FontWeight.w700,
          color: scheme.error,
        ),
      );
    } else {
      final a = anpfiff?.toLocal();
      rechts = Text(
        a == null ? '' : DateFormat('EE, d. MMM', 'de_DE').format(a),
        style: TextStyle(
          fontSize: Schrift.label,
          fontWeight: FontWeight.w600,
          color: leise,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Abstand.m - 2,
          vertical: 10,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                'ST ${spiel.runde}',
                style: TextStyle(
                  fontSize: Schrift.label,
                  fontWeight: FontWeight.w700,
                  color: leise,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: Abstand.s),
            if (spiel.spielfrei)
              const SizedBox(width: 26)
            else
              AppAvatar(
                imageUrl: gegner?.avatarUrl,
                emoji: gegner?.avatarEmoji,
                colorHex: gegner?.avatarColor,
                fallbackText: name,
                size: 26,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: Schrift.text,
                  fontWeight: FontWeight.w600,
                  color: spiel.spielfrei ? leise : scheme.onSurface,
                ),
              ),
            ),
            const SizedBox(width: Abstand.s),
            rechts,
          ],
        ),
      ),
    );
  }
}

/// S, U oder N als kleine Marke. **Farbe tragen nur Sieg und Niederlage** —
/// dieselbe Regel wie bei den Trade-Ausgängen: Ein Unentschieden ist kein
/// Ergebnis, das etwas sagt, und bleibt neutral.
class _AusgangMarke extends StatelessWidget {
  const _AusgangMarke(this.ausgang);

  final DuellAusgang ausgang;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (buchstabe, farbe, wort) = switch (ausgang) {
      DuellAusgang.sieg => ('S', MatchUpColors.green, 'Sieg'),
      DuellAusgang.niederlage => ('N', scheme.error, 'Niederlage'),
      DuellAusgang.unentschieden => (
        'U',
        scheme.onSurfaceVariant,
        'Unentschieden',
      ),
    };
    return Semantics(
      label: wort,
      excludeSemantics: true,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          buchstabe,
          style: TextStyle(
            fontSize: Schrift.label,
            fontWeight: FontWeight.w800,
            color: farbe,
          ),
        ),
      ),
    );
  }
}

class _Trenner extends StatelessWidget {
  const _Trenner();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: Abstand.m - 2,
    endIndent: Abstand.m - 2,
    color: Theme.of(context).dividerColor,
  );
}

class _Leer extends StatelessWidget {
  const _Leer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Abstand.s),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}
