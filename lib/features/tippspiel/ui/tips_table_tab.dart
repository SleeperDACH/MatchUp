import '../../../app/farben.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/round_table.dart';
import '../logic/tip_scoring.dart';
import '../logic/tip_weeks.dart';
import '../models/tip.dart';
import '../models/tip_round.dart';
import '../providers.dart';
import 'round_selector.dart';
import 'tip_member_profile_sheet.dart';
import '../../../app/widgets/karte.dart';
import '../../../app/widgets/punktzahl.dart';
import '../../../app/typografie.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import 'package:intl/intl.dart';
import '../../../core/data/sportmonks/sportmonks_provider.dart';

/// Signalfarbe für laufende Spiele (Spielstand & vorläufige Punkte).

/// Feste Höhen für die zwei nebeneinanderliegenden Tabellenhälften
/// (eingefrorene Namen + scrollende Ergebnisse) — nur so fluchten die
/// Zeilen über die Trennlinie hinweg.
const double _kopfHoehe = 52;
const double _zeilenHoehe = 50;
const double _spaltenBreite = 54;
const double _namenBreite = 178;

/// Tipp-Tabelle à la Kicktipp: alle Mitglieder als Zeilen, die Spiele
/// der gewählten Runde als Spalten. Fremde Tipps erscheinen erst nach
/// Anstoß (serverseitig erzwungen); pro Tipp gibt es die Punkte nach
/// Kicktipp-System, sortiert wird nach Gesamtpunkten. Laufende Spiele
/// sind farblich (orange) markiert und zählen live mit.
class TipsTableTab extends ConsumerWidget {
  const TipsTableTab({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Multi-Wettbewerb-Runden navigieren über Spielwochen (Do–Mi) statt über
    // den Spieltag eines einzelnen Wettbewerbs.
    if (round.competitions.length > 1) return _WeekTable(round: round);

    final league = ref.watch(selectedLeagueProvider);
    final currentRound = ref.watch(currentRoundProvider);

    return currentRound.when(
      loading: () => const Skelett(),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (current) {
        final matchday = ref.watch(selectedRoundProvider) ?? current;
        return Column(
          children: [
            RoundSelector(league: league, round: matchday),
            Expanded(
              child: _TableBody(round: round, matchday: matchday),
            ),
          ],
        );
      },
    );
  }
}

/// Tabellen-Rahmen für Multi-Wettbewerb-Runden: Wochen-Selektor + die Spiele
/// der gewählten Woche als Spalten. Die Punkte-Summen bleiben
/// wettbewerbsübergreifend (unverändert in [_TableBody]).
class _WeekTable extends ConsumerWidget {
  const _WeekTable({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weeksAsync = ref.watch(roundWeeksProvider);
    return weeksAsync.when(
      loading: () => const Skelett(),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (weeks) {
        if (weeks.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Keine Spiele gefunden.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final selected = ref.watch(selectedWeekProvider);
        final index = selected ?? currentWeekIndex(weeks, DateTime.now());
        TipWeek week = weeks.last;
        for (final w in weeks) {
          if (w.index == index) {
            week = w;
            break;
          }
        }
        return Column(
          children: [
            WeekSelector(weeks: weeks, index: week.index),
            Expanded(
              child: _TableBody(
                round: round,
                matchday: 0,
                weekFixtures: week.fixtures,
                weekStart: week.start,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TableBody extends ConsumerStatefulWidget {
  const _TableBody({
    required this.round,
    required this.matchday,
    this.weekFixtures,
    this.weekStart,
  });

  final TipRound round;

  /// Spieltag (Einzel-Liga-Pfad). Im Wochen-Pfad ungenutzt.
  final int matchday;

  /// Gesetzt im Wochen-Pfad: die Spiele der gewählten Woche als Spalten.
  /// `null` ⇒ Spieltag-Pfad (Spalten aus [roundFixturesProvider]).
  final List<Fixture>? weekFixtures;

  /// Wochenbeginn (Do 00:00) — Schnitt für die Bewegungspfeile im Wochen-Pfad.
  final DateTime? weekStart;

  @override
  ConsumerState<_TableBody> createState() => _TableBodyState();
}

class _TableBodyState extends ConsumerState<_TableBody> {
  /// Auto-Refresh, solange ein Spiel der Runde live ist.
  Timer? _liveTimer;

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  /// Startet/stoppt den 60-Sekunden-Takt je nachdem, ob gerade ein
  /// Spiel läuft — kein Polling, wenn alles beendet/geplant ist.
  void _syncAutoRefresh(bool hasLive) {
    if (hasLive && _liveTimer == null) {
      _liveTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _refresh(),
      );
    } else if (!hasLive && _liveTimer != null) {
      _liveTimer!.cancel();
      _liveTimer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final weekMode = widget.weekFixtures != null;
    final membersAsync = ref.watch(roundMembersProvider(round.id));
    final tipsAsync = ref.watch(allRoundTipsProvider(round.id));
    // Spalten-Spiele: im Wochen-Pfad die übergebenen Fixtures, sonst der
    // Spieltag des einzelnen Wettbewerbs.
    final fixturesAsync = weekMode
        ? null
        : ref.watch(roundFixturesProvider(widget.matchday));
    // Saison-Fixtures ALLER Wettbewerbe der Runde → gemeinsame Wertung über
    // mehrere Wettbewerbe (Tipps sind fixture-basiert und liga-übergreifend).
    final seasonAsyncs = [
      for (final id in round.competitions)
        ref.watch(leagueSeasonFixturesProvider(id)),
    ];
    final seasonFehlt = seasonAsyncs.any((a) => a.valueOrNull == null);
    final seasonError = seasonAsyncs
        .map((a) => a.error)
        .firstWhere((e) => e != null, orElse: () => null);

    // **Der Spinner ersetzt die Tabelle nur, wenn es keine gibt.** Gefragt ist
    // „liegen Daten vor?", nicht „lädt gerade etwas?" — sonst fällt der Schirm
    // bei jedem Nachladen auf einen leeren Kreis zurück, und die Tipps laden
    // an einem Spieltag alle 30 Sekunden nach.
    if (membersAsync.valueOrNull == null ||
        tipsAsync.valueOrNull == null ||
        (fixturesAsync != null && fixturesAsync.valueOrNull == null) ||
        seasonFehlt) {
      return const Skelett();
    }
    final error =
        membersAsync.error ??
        tipsAsync.error ??
        fixturesAsync?.error ??
        seasonError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tabelle konnte nicht geladen werden.\n$error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _refresh,
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
    }

    final members = [...membersAsync.requireValue];
    final tips = tipsAsync.requireValue;
    final fixtures = weekMode
        ? widget.weekFixtures!
        : fixturesAsync!.requireValue;
    final seasonFixtures = [
      for (final a in seasonAsyncs) ...(a.valueOrNull ?? const <Fixture>[]),
    ];
    final rules = round.scoring;
    final myUserId = ref.watch(currentUserProvider)?.id;
    // Eingefrorene Quoten für den Bonus; blockiert die Tabelle nicht,
    // wenn sie (noch) fehlen — dann gibt es schlicht keinen Bonus.
    final frozenOdds =
        ref.watch(frozenOddsProvider).valueOrNull ??
        const <String, FrozenOdds>{};
    // Wer hat (verborgen) getippt? Nur Existenz, für das Schloss-Symbol.
    final tipPresence =
        ref.watch(tipPresenceProvider(round.id)).valueOrNull ??
        const <String>{};

    final totals = totalPointsByMember(
      members: members,
      tips: tips,
      fixtures: seasonFixtures,
      rules: rules,
      frozenOdds: frozenOdds,
    );
    members.sort((a, b) {
      final byPoints = (totals[b.userId] ?? 0) - (totals[a.userId] ?? 0);
      return byPoints != 0
          ? byPoints
          : a.display.toLowerCase().compareTo(b.display.toLowerCase());
    });

    // Platzierung + Bewegung ggü. dem Stand vor dem gewählten Spieltag.
    final currentRanks = ranksByPoints(members, totals);
    // Bewegungspfeile: Stand vor der aktuellen Ansicht. Im Wochen-Pfad alle
    // Spiele vor Wochenbeginn, sonst alle Spiele früherer Spieltage.
    final priorFixtures = [
      for (final f in seasonFixtures)
        if (weekMode
            ? f.kickoff.isBefore(widget.weekStart!)
            : f.round < widget.matchday)
          f,
    ];
    final hasPrior = priorFixtures.any((f) => f.hasScore);
    final priorRanks = hasPrior
        ? ranksByPoints(
            members,
            totalPointsByMember(
              members: members,
              tips: tips,
              fixtures: priorFixtures,
              rules: rules,
              frozenOdds: frozenOdds,
            ),
          )
        : const <String, int>{};

    final tipByMemberAndFixture = {
      for (final t in tips) '${t.userId}|${t.fixtureId}': t,
    };

    // Auto-Refresh nur, solange ein Spiel der Runde läuft (Seiteneffekt,
    // löst selbst keinen Rebuild aus).
    _syncAutoRefresh(fixtures.any((f) => f.status == FixtureStatus.live));

    final spiele = [...fixtures]
      ..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final scheme = Theme.of(context).colorScheme;
    final linie = scheme.onSurface.withValues(alpha: 0.07);
    final ichFlaeche = scheme.onSurface.withValues(alpha: 0.05);

    // **Zwei fluchtende Hälften in einer Karte** (Format seit jeher, Aussehen
    // seit 10.11.2026): links Platz, Name und Summe eingefroren, rechts die
    // Spiele zum Querwischen. Gleiche feste Höhen halten die Zeilen über die
    // Trennlinie hinweg auf einer Linie. Eigene Zeilen statt `DataTable` —
    // dessen Kopf, Abstände und Linien ließen sich nicht an die App anpassen.
    BoxDecoration zeile(String userId, {bool erste = false}) => BoxDecoration(
          color: userId == myUserId ? ichFlaeche : null,
          border: erste ? null : Border(top: BorderSide(color: linie)),
        );

    final links = Column(
      children: [
        SizedBox(
          height: _kopfHoehe,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(child: _KopfText('Spieler')),
                _KopfText('Pkt.'),
              ],
            ),
          ),
        ),
        for (final m in members)
          InkWell(
            onTap: () =>
                showTipMemberProfile(context, round: round, member: m),
            child: Container(
              height: _zeilenHoehe,
              padding: const EdgeInsets.only(left: 10, right: 10),
              decoration: zeile(m.userId),
              child: _NameCell(
                rank: currentRanks[m.userId] ?? 0,
                movement: hasPrior
                    ? (priorRanks[m.userId] ?? 0) -
                          (currentRanks[m.userId] ?? 0)
                    : null,
                username: m.display,
                isMe: m.userId == myUserId,
                avatar: (
                  url: m.avatarUrl,
                  emoji: m.avatarEmoji,
                  color: m.avatarColor,
                ),
                punkte: totals[m.userId] ?? 0,
              ),
            ),
          ),
      ],
    );

    final rechts = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        children: [
          SizedBox(
            height: _kopfHoehe,
            child: Row(
              children: [
                for (final f in spiele) _FixtureHeader(fixture: f),
              ],
            ),
          ),
          for (final m in members)
            Container(
              height: _zeilenHoehe,
              decoration: zeile(m.userId),
              child: Row(
                children: [
                  for (final f in spiele)
                    SizedBox(
                      width: _spaltenBreite,
                      child: _TipCell(
                        tip: tipByMemberAndFixture['${m.userId}|${f.id}'],
                        fixture: f,
                        hasHiddenTip: tipPresence.contains(
                          '${m.userId}|${f.id}',
                        ),
                        rules: rules,
                        odds: frozenOdds[f.id],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Kapitelmarke(
            'Tabelle',
            obenLuft: Abstand.s,
            info: (
              'Punkte',
              'Exaktes Ergebnis ${rules.exact}, richtige Tordifferenz '
                  '${rules.goalDiff}, richtige Tendenz ${rules.tendency}'
                  '${rules.oddsBonus ? ', dazu der Quoten-Bonus (★)' : ''}. '
                  'Die Tipps der anderen sind ab Anstoß sichtbar — vorher '
                  'zeigt ein Schloss, dass schon getippt ist.',
            ),
          ),
          Container(
            decoration: kartenDeko(context),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _namenBreite,
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: linie)),
                    ),
                    child: links,
                  ),
                  if (spiele.isNotEmpty) Expanded(child: rechts),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refresh() {
    sportmonksBuendel.leeren();
    ref.invalidate(roundMembersProvider(widget.round.id));
    ref.invalidate(allRoundTipsProvider(widget.round.id));
    ref.invalidate(tipPresenceProvider(widget.round.id));
    if (widget.weekFixtures != null) {
      ref.invalidate(roundWeeksProvider);
    } else {
      ref.invalidate(roundFixturesProvider(widget.matchday));
    }
    for (final id in widget.round.competitions) {
      ref.invalidate(leagueSeasonFixturesProvider(id));
    }
  }
}

/// Spaltenkopf-Beschriftung („Spieler", „Pkt.").
class _KopfText extends StatelessWidget {
  const _KopfText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: Schrift.label,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

/// Namens-Zelle: Platz (1 in Gold), Bewegung, Profilbild, Name — und die
/// Summe am rechten Rand, kräftig und mit gleichbreiten Ziffern.
class _NameCell extends StatelessWidget {
  const _NameCell({
    required this.rank,
    required this.movement,
    required this.username,
    required this.isMe,
    required this.punkte,
    this.avatar,
  });

  final int rank;

  /// >0 = aufgestiegen, <0 = abgestiegen, 0 = gleich, null = kein Vergleich.
  final int? movement;
  final String username;
  final bool isMe;
  final int punkte;
  final AvatarInfo? avatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 16,
          child: Text(
            '$rank',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: Schrift.label,
              color: rank == 1 ? context.farben.gold : scheme.onSurfaceVariant,
              fontFeatures: gleichbreiteZiffern,
            ),
          ),
        ),
        SizedBox(width: 10, child: _arrow(context)),
        AppAvatar(
          imageUrl: avatar?.url,
          emoji: avatar?.emoji,
          colorHex: avatar?.color,
          fallbackText: username,
          size: 22,
        ),
        const SizedBox(width: 6),
        Expanded(
          // **Namen schrumpfen, sie brechen nicht ab** — man soll Leute
          // wiedererkennen; lieber eine Spur kleiner als „Spitzenr…".
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              username,
              maxLines: 1,
              style: TextStyle(
                fontSize: Schrift.text,
                fontWeight: isMe ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$punkte',
          style: const TextStyle(
            fontSize: Schrift.text,
            fontWeight: FontWeight.w800,
            fontFeatures: gleichbreiteZiffern,
          ),
        ),
      ],
    );
  }

  Widget _arrow(BuildContext context) {
    final m = movement;
    if (m == null || m == 0) return const SizedBox.shrink();
    return Icon(
      m > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
      color: m > 0 ? context.farben.gruen : context.farben.rot,
      size: 18,
    );
  }
}

/// Spaltenkopf: Vereinskürzel als Beschriftung, darunter der Stand.
///
/// **Rot sagt „läuft", ohne es hinzuschreiben** (gemeldet: „das Live bitte
/// wegnehmen, es reicht, wenn das Ergebnis rot ist"). Ohne Stand steht der
/// Anstoßtag — eine Spalte voller Schlösser sagt sonst nicht, wann es losgeht.
class _FixtureHeader extends StatelessWidget {
  const _FixtureHeader({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    return SizedBox(
      width: _spaltenBreite,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final name in [f.home.name, f.away.name])
            Text(
              vereinsKuerzel(name),
              maxLines: 1,
              style: TextStyle(
                fontSize: Schrift.mikro,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                height: 1.25,
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 2),
          Text(
            f.hasScore
                ? '${f.homeScore}:${f.awayScore}'
                : DateFormat('E', 'de_DE').format(f.kickoff.toLocal()),
            style: TextStyle(
              fontSize: f.hasScore ? Schrift.text : Schrift.label,
              fontWeight: f.hasScore ? FontWeight.w800 : FontWeight.w600,
              color: live
                  ? context.farben.rot
                  : (f.hasScore ? null : scheme.onSurfaceVariant),
              fontFeatures: gleichbreiteZiffern,
            ),
          ),
        ],
      ),
    );
  }
}

class _TipCell extends StatelessWidget {
  const _TipCell({
    required this.tip,
    required this.fixture,
    required this.hasHiddenTip,
    required this.rules,
    required this.odds,
  });

  final MemberTip? tip;
  final Fixture fixture;

  /// Es existiert ein (vor Anstoß verborgener) Tipp für diese Zelle.
  final bool hasHiddenTip;
  final ScoringRules rules;
  final FrozenOdds? odds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Kein sichtbarer Tipp: verborgen getippt → Schloss, sonst ein leiser
    // Strich (eine leere Zelle sah aus wie ein Ladefehler).
    if (tip == null) {
      return Center(
        child: hasHiddenTip
            ? Icon(
                Icons.lock_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              )
            : Text(
                '–',
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.25),
                ),
              ),
      );
    }

    final text = Text(
      '${tip!.homeGoals}:${tip!.awayGoals}',
      style: const TextStyle(
        fontSize: Schrift.text,
        fontWeight: FontWeight.w700,
        fontFeatures: gleichbreiteZiffern,
      ),
    );
    if (!fixture.hasScore) return Center(child: text);

    final live = fixture.status == FixtureStatus.live;
    final base = scoreTip(
      tipHome: tip!.homeGoals,
      tipAway: tip!.awayGoals,
      resultHome: fixture.homeScore!,
      resultAway: fixture.awayScore!,
      rules: rules,
    );
    final bonus = rules.oddsBonus
        ? oddsBonus(
            tipHome: tip!.homeGoals,
            tipAway: tip!.awayGoals,
            resultHome: fixture.homeScore!,
            resultAway: fixture.awayScore!,
            homeWin: odds?.homeWin,
            draw: odds?.draw,
            awayWin: odds?.awayWin,
            rules: rules,
          )
        : 0;
    final points = base + bonus;
    // **Grün nur für den Volltreffer**, null Punkte gedämpft, laufend rot.
    // Die Punkte stehen als kleine Marke unter dem Tipp: getönte Fläche in
    // der Signalfarbe, damit der Blick über eine Spalte die Treffer findet.
    final exakt = base >= rules.exact;
    final farbe = live
        ? context.farben.rot
        : points == 0
        ? scheme.onSurfaceVariant
        : exakt
        ? context.farben.gruen
        : scheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          text,
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: points == 0 ? null : farbe.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              bonus > 0 ? '+$points ★' : '+$points',
              style: TextStyle(
                fontSize: Schrift.mikro,
                fontWeight: FontWeight.w800,
                color: farbe,
                fontFeatures: gleichbreiteZiffern,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
