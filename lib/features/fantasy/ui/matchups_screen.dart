import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logic/round_robin.dart';
import '../../../core/models/models.dart';
import '../../../core/ui/app_avatar.dart';
import '../../auth/providers.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../logic/h2h_grundlage.dart';
import '../providers.dart';
import 'matchday_stepper.dart';
import 'matchup_hero.dart';
import 'manager_profile_screen.dart';
import 'matchup_lineups.dart';
import 'roster_limit_banner.dart';

/// Eigenständiger Screen (mit AppBar) — dünne Hülle um [MatchupsBody].
class MatchupsScreen extends StatelessWidget {
  const MatchupsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchups')),
      body: MatchupsBody(league: league),
    );
  }
}

/// Head-to-Head-Matchups: pro Spieltag 1-gegen-1-Paarungen plus die
/// Saison-Bilanztabelle (Siege-Niederlagen-Unentschieden). Der Spielplan
/// ist deterministisch aus der Manager-Reihenfolge (Round-Robin).
/// Body ohne Scaffold, damit er als Tab einsetzbar ist.
/// **Auf welchem MatchUp der Nutzer steht** — je Liga, ausserhalb des Widgets.
///
/// Vorher stand die Zahl als `_bannerPage` im State. Das reichte nicht: Wer
/// vom MatchUp-Reiter auf Kader oder Tabelle wechselt, laesst den Teilbaum
/// abbauen — `TabBarView` haelt nur die Nachbarn am Leben —, und mit ihm stirbt
/// der State. Beim Zurueckkommen stand die Karte oben zwar noch richtig (ihre
/// Position liegt im `PageStorage`), die **Aufstellungen darunter** aber
/// wieder auf der eigenen Paarung. Gemeldet wurde genau das: „wird mir wieder
/// SFV03 gegen JojoAcz angezeigt".
///
/// Zwei Merker fuer eine Sache waren der Fehler. Jetzt gibt es einen, und der
/// ueberlebt auch einen Reiterwechsel.
final matchupKarussellSeiteProvider =
    StateProvider.family<int, String>((ref, ligaId) => 0);

/// **Sprung aus der Liga-Übersicht:** Ein Tipp auf den MatchUp-Kasten dort
/// zählt diesen Zähler hoch und wechselt in den Reiter. Der MatchUp-Tab hört
/// darauf und stellt sich auf das **eigene** Duell des **aktuellen** Spieltags —
/// auch wenn man vorher weitergewischt oder eine andere Woche gewählt hatte.
/// Ein Zähler statt eines Wahrheitswerts, damit zwei Sprünge hintereinander
/// zweimal wirken.
final matchupSprungProvider =
    StateProvider.family<int, String>((ref, ligaId) => 0);

class MatchupsBody extends ConsumerStatefulWidget {
  const MatchupsBody({super.key, required this.league});

  final FantasyLeague league;

  @override
  ConsumerState<MatchupsBody> createState() => _MatchupsBodyState();
}

class _MatchupsBodyState extends ConsumerState<MatchupsBody> {
  // Hoher Startindex, damit man in beide Richtungen „endlos" wischen kann;
  // die tatsächliche Paarung ergibt sich per Modulo (zyklisches Karussell).
  static const _loopBase = 100000;

  int? _round;

  /// **Der Controller startet auf der gemerkten Seite**, nicht stur auf der
  /// ersten — und die liegt im Provider, nicht im State.
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    // **Hier, nicht als `late final`-Ausdruck.** Der lief erst beim ersten
    // Zugriff — und wenn der Schirm nie ein Karussell gebaut hatte (weil er
    // auf dem Fehler- oder Ladezustand stand), war das `dispose()`. Dort ist
    // `ref` schon tot: „Cannot use ref after the widget was disposed",
    // geworfen beim Verlassen des Tabs. In `initState` ist `ref.read` erlaubt
    // und der Zeitpunkt eindeutig.
    _pageController = PageController(
      initialPage:
          _loopBase + ref.read(matchupKarussellSeiteProvider(widget.league.id)),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Effektive Punkte aller Manager für einen Spieltag (geteilte Logik).
  Map<String, double> _totals(
    Map<String, PlayerMatchStats> stats,
    int round, {
    required List<FantasyManager> managers,
    required List<RosterEntry> roster,
    required Map<String, FantasyPlayer> playerById,
    required List<FantasyLineup> lineups,
  }) =>
      effectiveTotalsForRound(
        stats: stats,
        round: round,
        managers: managers,
        roster: roster,
        playerById: playerById,
        lineups: lineups,
        scoring: widget.league.scoring,
        rosterConfig: widget.league.roster,
      );

  @override
  Widget build(BuildContext context) {
    final league = widget.league;
    ref.listen(matchupSprungProvider(league.id), (_, _) {
      setState(() => _round = null);
      // Auf die gemerkte Seite, nicht stur auf die erste: Das Duell-Band im
      // Tabellen-Reiter springt auf eine beliebige Paarung (16.10.2026).
      if (_pageController.hasClients) {
        _pageController.jumpToPage(
            _loopBase + ref.read(matchupKarussellSeiteProvider(league.id)));
      }
    });
    final current = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final round = _round ?? current ?? 1;

    final managersAsync = ref.watch(fantasyManagersProvider(league.id));
    final poolAsync = ref.watch(playerPoolProvider);
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final lineups = ref.watch(leagueLineupsProvider(league.id)).valueOrNull ??
        const <FantasyLineup>[];
    final weekStats = ref.watch(roundStatsProvider(round)).valueOrNull ?? const {};
    final seasonStats = ref.watch(seasonStatsProvider).valueOrNull ?? const {};
    final allFx =
        ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
    final myId = ref.watch(currentUserProvider)?.id;

    // **Nur beim allerersten Laden ein Spinner, nicht bei jedem Nachladen.**
    //
    // Vorher stand hier `isLoading`, und das war die Ursache für „es wirft
    // einen zurück auf das erste MatchUp": Der frühe `return` ersetzt den
    // ganzen Teilbaum, der `PageView` wird abgebaut, und beim Wiederaufbau
    // beginnt der Controller wieder bei `initialPage`. Ausgelöst hat das jede
    // Auffrischung — der Spielerpool wird nachgeladen, sobald ein Profil
    // aufgeht, und `fantasyManagersProvider` meldet beim Wiederverbinden
    // ebenfalls kurz „lädt".
    //
    // Maßgeblich ist deshalb, ob **Daten da sind**, nicht ob gerade geladen
    // wird. Ein Nachladen über vorhandenen Daten darf man nicht sehen.
    // **Derselbe Grundsatz gilt für den Fehler, und das war er nicht.**
    //
    // Der Spinner hing schon an „sind Daten da?" — der Fehlerschirm dagegen
    // an „ist ein Fehler gemeldet?", ganz unabhängig davon. Und
    // `fantasyManagersProvider` ist ein Realtime-Stream: Reißt die Verbindung
    // ab (was während eines Spieltags immer wieder vorkommt), meldet er einen
    // Fehler und liefert den letzten Stand trotzdem mit. Der Tab wurde damit
    // durch „Matchups konnten nicht geladen werden" ersetzt, obwohl die Daten
    // vollständig dalagen — gemeldet als „ich muss alle 3 Sekunden erneut
    // laden, obwohl nur eine Verbindung abbricht".
    //
    // Nebenwirkung, die derselbe frühe `return` hatte: Er baut den `PageView`
    // ab, also fiel das Karussell dabei auch noch auf das erste MatchUp
    // zurück.
    //
    // **Ein Fehler ersetzt den Schirm nur, wenn es nichts zu zeigen gibt.**
    // Liegen Daten vor, bleiben sie stehen; der Stream verbindet sich von
    // selbst wieder, und ein Stand von vor zehn Sekunden ist allemal besser
    // als ein leerer Tab mit einem Knopf.
    final hatDaten =
        managersAsync.valueOrNull != null && poolAsync.valueOrNull != null;
    if (!hatDaten) {
      final loadError = managersAsync.error ?? poolAsync.error;
      if (loadError == null) {
        return const Skelett();
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Matchups konnten nicht geladen werden.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  ref.invalidate(fantasyManagersProvider(league.id));
                  ref.invalidate(playerPoolProvider);
                },
                child: const Text('Erneut laden'),
              ),
            ],
          ),
        ),
      );
    }
    return Builder(builder: (context) {
              // `valueOrNull` statt `requireValue`: Beim Nachladen über
              // vorhandenen Daten liefert Riverpod den alten Stand mit, und
              // genau den wollen wir weiterzeigen.
              final managers = managersAsync.valueOrNull ?? const [];
              final pool = poolAsync.valueOrNull ?? const <FantasyPlayer>[];
              final playerById = {for (final p in pool) p.id: p};
              final nameOf = {for (final m in managers) m.userId: m.display};
              final avatarOf = {
                for (final m in managers)
                  m.userId: (
                    url: m.avatarUrl,
                    emoji: m.avatarEmoji,
                    color: m.avatarColor
                  )
              };

              // Stabile Reihenfolge: Draft-Position, dann User-ID.
              final ids = managers.map((m) => m.userId).toList()
                ..sort((a, b) {
                  final ma = managers.firstWhere((m) => m.userId == a);
                  final mb = managers.firstWhere((m) => m.userId == b);
                  final pa = ma.draftPosition ?? 1 << 30;
                  final pb = mb.draftPosition ?? 1 << 30;
                  return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
                });

              if (ids.length < 2) {
                // Noch keine Paarungen möglich — aber die Teamliste (du + freie
                // Plätze bis zur Teilnehmerzahl) schon anzeigen.
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Text(
                        'Head-to-Head startet, sobald ein zweiter Spieler '
                        'beitritt. Teile dazu den Einladungscode – neue Spieler '
                        'füllen automatisch die freien Teams auf.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text('Teams',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    for (final id in ids)
                      ListTile(
                        dense: true,
                        leading: AppAvatar(
                          imageUrl: avatarOf[id]?.url,
                          emoji: avatarOf[id]?.emoji,
                          colorHex: avatarOf[id]?.color,
                          fallbackText: nameOf[id],
                          size: 32,
                        ),
                        title: Text(nameOf[id] ?? '?',
                            style: id == myId
                                ? const TextStyle(fontWeight: FontWeight.bold)
                                : null),
                      ),
                    if (league.maxTeams != null)
                      for (var k = ids.length; k < league.maxTeams!; k++)
                        _EmptyTeamRow(teamNo: k + 1),
                  ],
                );
              }

              final weekTotals = _totals(weekStats, round,
                  managers: managers,
                  roster: roster,
                  playerById: playerById,
                  lineups: lineups);
              final pairings = roundPairings(ids, round);

              // Live-/Beendet-Status des Spieltags aus den Fixtures.
              final roundFx = [
                for (final f in allFx)
                  if (f.round == round) f
              ];
              final live = roundIsLive(roundFx, DateTime.now());
              // Frühester Anpfiff des Spieltags — steht in der Vorschau unter
              // dem „VS" (siehe `_VsPlatte`).
              final anpfiff = roundFx.isEmpty
                  ? null
                  : roundFx
                      .map((f) => f.kickoff)
                      .reduce((a, b) => a.isBefore(b) ? a : b);
              final started = live ||
                  (roundFx.isNotEmpty &&
                      roundFx.every((f) => f.status == FixtureStatus.finished));

              // Eigene Paarung zuerst (Platz 1), dann die übrigen — wischbar.
              final myPairing = myId == null
                  ? null
                  : pairings
                      .where((m) => m.home == myId || m.away == myId)
                      .firstOrNull;
              final ordered = <Matchup>[
                ?myPairing,
                for (final m in pairings)
                  if (myPairing == null || !identical(m, myPairing)) m,
              ];
              // Anzeige-Reihenfolge: bei der eigenen Paarung stehe ich links.
              (String, String?) sidesOf(Matchup p) {
                if (p.isBye) return (p.home, null);
                if (p.away == myId) return (p.away!, p.home);
                return (p.home, p.away);
              }

              // **Bilanz und Prognose aus denselben Funktionen wie der Kasten
              // auf der Liga-Übersicht** (`bannerBilanz`, `duellPrognose`) —
              // für dasselbe Duell stehen an beiden Orten dieselben Zahlen.
              //
              // Bilanz und Schnitte rechnen nur über **abgepfiffene**
              // Spieltage: Der laufende trägt Zwischenstände, und eine Bilanz
              // ist ein Ergebnis.
              final abgepfiffen = ref.watch(abgepfiffeneRundenProvider);
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
              final ausfaelle =
                  ref.watch(absencesProvider).valueOrNull ?? const {};
              final wochenStreuung =
                  ref.watch(fantasyWochenStreuungProvider(league.id));
              final jetzt = DateTime.now();
              MatchupSideData seite(String id) => computeSideData(
                    league: league,
                    round: round,
                    managerId: id,
                    byId: playerById,
                    roster: roster,
                    lineups: lineups,
                    stats: weekStats,
                  );

              final gemerkt =
                  ref.watch(matchupKarussellSeiteProvider(league.id));
              final page =
                  ordered.isEmpty ? 0 : gemerkt.clamp(0, ordered.length - 1);

              return ListView(
                children: [
                  if (myId != null)
                    RosterLimitBanner(
                        count: rosterCountOf(myId, roster),
                        limit: league.roster.squadSize),
                  if (ref.watch(roundStatsProvider(round)).isLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  // Wischbares Banner-Karussell: eigene Paarung auf Platz 1.
                  SizedBox(
                    // Feste Höhe, weil der PageView eine braucht — die Zahl
                    // gehört aber zum Banner und steht deshalb dort.
                    height: kMatchupBannerHoehe,
                    child: PageView.builder(
                      // **Ohne diesen Schlüssel merkt sich der PageView
                      // nichts.** `PageController.keepPage` steht auf `true`,
                      // aber `PageStorage` schreibt und liest nur, wenn im
                      // Widget-Pfad ein `PageStorageKey` liegt — sonst ist die
                      // Kennung leer und beide Aufrufe tun stillschweigend
                      // nichts.
                      //
                      // Das Karussell sitzt in einem gewöhnlichen `ListView`.
                      // Scrollt es weiter als dessen Vorrat (250 Punkte) aus
                      // dem Sichtfeld, wird es abgebaut; beim Zurückscrollen
                      // entsteht eine neue Scroll-Position, und ohne
                      // gespeicherten Stand beginnt sie bei `initialPage`.
                      //
                      // Genau das war die Meldung: Der Punkt darunter blieb
                      // auf dem dritten MatchUp (er hängt an `_bannerPage` im
                      // State und überlebt), die Karte darüber sprang auf das
                      // erste — und ein Wisch nach rechts führte deshalb zum
                      // zweiten statt zum vierten.
                      key: const PageStorageKey('matchup-karussell'),
                      controller: _pageController,
                      onPageChanged: (i) => ref
                              .read(matchupKarussellSeiteProvider(league.id)
                                  .notifier)
                              .state =
                          ((i - _loopBase) % ordered.length + ordered.length) %
                              ordered.length,
                      // itemCount offen lassen -> zyklisch in beide Richtungen.
                      itemBuilder: (context, i) {
                        final logical =
                            ((i - _loopBase) % ordered.length + ordered.length) %
                                ordered.length;
                        final p = ordered[logical];
                        final (hId, aId) = sidesOf(p);
                        final prognose = duellPrognose(
                          round: round,
                          heim: seite(hId),
                          gast: aId == null ? null : seite(aId),
                          spiele: allFx,
                          saisonGewertet: saisonGewertet,
                          regeln: league.scoring,
                          ausfaelle: ausfaelle,
                          wochenStreuung: wochenStreuung,
                          jetzt: jetzt,
                        );
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          child: MatchupBanner(
                            round: round,
                            remisGrenze: league.remisGrenze ?? 0,
                            homeName: nameOf[hId] ?? '?',
                            awayName: aId == null ? null : (nameOf[aId] ?? '?'),
                            homePoints: weekTotals[hId] ?? 0.0,
                            awayPoints:
                                aId == null ? 0.0 : (weekTotals[aId] ?? 0.0),
                            homeMe: hId == myId,
                            awayMe: aId == myId,
                            homeAvatar: ManagerAvatar(
                              userId: hId,
                              url: avatarOf[hId]?.url,
                              emoji: avatarOf[hId]?.emoji,
                              color: avatarOf[hId]?.color,
                            ),
                            awayAvatar: aId == null
                                ? null
                                : ManagerAvatar(
                                    userId: aId,
                                    url: avatarOf[aId]?.url,
                                    emoji: avatarOf[aId]?.emoji,
                                    color: avatarOf[aId]?.color,
                                  ),
                            live: live,
                            started: started,
                            mine: hId == myId || aId == myId,
                            homeBilanz: bannerBilanz(grundlage, hId),
                            awayBilanz: aId == null
                                ? null
                                : bannerBilanz(grundlage, aId),
                            anpfiff: anpfiff,
                            homeErwartet: prognose.heimErwartet,
                            awayErwartet: prognose.gastErwartet,
                            siegchanceHeim: prognose.siegchanceHeim,
                            // **Kein Tipp-Ziel im MatchUp-Tab.** Er öffnete
                            // die Detailseite — dasselbe Duell noch einmal,
                            // in einem abgeschlossenen Bereich. Man ist hier
                            // schon (auf Ansage, 14.10.2026).
                            onTap: null,
                            // **Bild und Name führen ins Ligaprofil** —
                            // dieselbe Regel wie über der Bank (Ansage vom
                            // 19.09.2026, nach dem Umbau erneut 14.10.2026).
                            onHomeName: () => showManagerProfile(
                              context,
                              league: league,
                              managerId: hId,
                              managerName: nameOf[hId] ?? '?',
                            ),
                            onAwayName: aId == null
                                ? null
                                : () => showManagerProfile(
                                      context,
                                      league: league,
                                      managerId: aId,
                                      managerName: nameOf[aId] ?? '?',
                                    ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (ordered.length > 1)
                    _Dots(count: ordered.length, active: page),
                  // **Der Spieltagswechsel sitzt über der Startelf**, wie bei
                  // Sleeper: Was man wechselt, sind die Aufstellungen darunter
                  // und der Kasten darüber. Vor der Kopfzeile stand er ganz
                  // oben über dem Karussell — als eigene Zeile, die mit dem
                  // Kasten um die Führung rang. Auch künftige Spieltage
                  // lassen sich so ansehen; der Kasten zeigt dort die Prognose.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'STARTELF',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(letterSpacing: 1.2),
                          ),
                        ),
                        MatchdayStepper(
                                kompakt: true,
                                round: round,
                          onChanged: (r) {
                            if (_pageController.hasClients) {
                              _pageController.jumpToPage(_loopBase);
                            }
                            ref
                                .read(matchupKarussellSeiteProvider(league.id).notifier)
                                .state = 0;
                            setState(() => _round = r);
                          },
                  ),
                      ],
                    ),
                  ),
                  // Aufstellungen der aktuell gewischten Paarung.
                  if (ordered.isNotEmpty)
                    Builder(builder: (context) {
                      final p = ordered[page];
                      final (hId, aId) = sidesOf(p);
                      final home = computeSideData(
                          league: league,
                          round: round,
                          managerId: hId,
                          byId: playerById,
                          roster: roster,
                          lineups: lineups,
                          stats: weekStats);
                      final away = aId == null
                          ? null
                          : computeSideData(
                              league: league,
                              round: round,
                              managerId: aId,
                              byId: playerById,
                              roster: roster,
                              lineups: lineups,
                              stats: weekStats);
                      // **Weich zwischen den Wochen** (Design-Ideen Punkt 6):
                      // Wer den Spieltag wechselt, sieht die Aufstellungen
                      // überblenden statt umspringen. Der Schlüssel ist
                      // Spieltag und Paarung — beides wechselt den Inhalt.
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (aktuell, vorige) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...vorige, ?aktuell],
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('$round|$hId|$aId'),
                          child: MatchupLineups(
                            league: league,
                            runde: round,
                            home: home,
                            away: away,
                            homeId: hId,
                            awayId: aId,
                            homeName: nameOf[hId] ?? '?',
                            awayName: aId == null ? null : (nameOf[aId] ?? '?'),
                            stats: weekStats,
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                ],
              );
            });
  }
}

/// Freier Team-Platz (Platzhalter) in der Bilanz-Liste — wird beim Beitritt
/// eines Spielers automatisch belegt.
class _EmptyTeamRow extends StatelessWidget {
  const _EmptyTeamRow({required this.teamNo});

  final int teamNo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Icon(Icons.person_add_alt_1,
            size: 15, color: scheme.onSurfaceVariant),
      ),
      title: Text('Team $teamNo',
          style: TextStyle(color: scheme.onSurfaceVariant)),
      trailing: Text('frei',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
    );
  }
}

/// Seiten-Indikator (Punkte) unter dem Banner-Karussell.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
