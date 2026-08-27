import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/vibrant_league_title.dart';
import '../../../app/widgets/team_fixture_list.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';
import '../../auth/providers.dart';
import '../../tippspiel/providers.dart';
import '../../tippspiel/ui/create_tip_round.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'roster_limit_banner.dart';
import 'draft_room_screen.dart';
import 'fantasy_chat_screen.dart';
import 'fantasy_settings_screen.dart';
import 'fantasy_table_screen.dart';
import 'free_agency_screen.dart';
import 'invite_players_screen.dart';
import 'lineup_screen.dart';
import 'matchup_hero.dart';
import 'matchups_screen.dart';
import 'player_pool_screen.dart';
import 'trade_screen.dart';
import 'weekly_recap_screen.dart';
import '../../../app/widgets/leise_reiter.dart';

/// Vollwertiger Fantasy-Liga-Screen mit Tabs. Zeigt schon vor dem Draft
/// Tabelle, Teilnehmer und (leeren) Kader an; die Übersicht führt durch
/// Setup und Draft.
class FantasyLeagueScreen extends ConsumerWidget {
  const FantasyLeagueScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Live-Status, damit Draft-Änderungen sofort durchschlagen.
    final live = ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final isAdmin = ref.watch(currentUserProvider)?.id == league.createdBy;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: VibrantLeagueTitle(
            name: live.name,
            subtitle: live.mode.label,
            logoUrl: live.logoUrl,
            logoEmoji: live.logoEmoji,
            logoColor: live.logoColor,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Einstellungen',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => FantasyLeagueSettingsScreen(league: live))),
            ),
          ],
          // Leise Reiter statt gefüllter Segmente: Der grüne Balken war das
          // lauteste Element des Schirms und sagte nur, welcher Reiter offen
          // ist. Die Symbole sind mit weggefallen — vier Wörter nebeneinander
          // brauchen keine Piktogramme, um unterscheidbar zu sein.
          bottom: const LeiseReiter(
            titel: ['Übersicht', 'MatchUp', 'Kader', 'Tabelle'],
            horizontal: 12,
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(league: live, isAdmin: isAdmin),
            MatchupsBody(league: live),
            _RostersTab(league: live),
            FantasyTableBody(league: live),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Übersicht
// ---------------------------------------------------------------------------

// Akzentfarben der Liga-Ansicht. `_cTeal` und `_cBlue` gehörten zu den
// „Schnellzugriff"-Kacheln und sind mit ihnen entfallen; die übrigen tragen
// noch Kader- und Tippspiel-Teile.
const _cGreen = MatchUpColors.green;
const _cAmber = Color(0xFFFFC83D);
const _cRed = MatchUpColors.red;
const _cBase = MatchUpColors.base;

/// Übersicht der Fantasy-Liga.
///
/// Umgesetzt ist „Richtung C" aus `design/liga-uebersicht/`: **Das Duell
/// führt.** In der laufenden Saison steht oben das eigene Head-to-Head, und
/// sein Sockel sagt, was ansteht („Aufstellung setzen"). Im Aufbau und im
/// Draft gibt es kein Duell — dort steht stattdessen der eine Auftrag, der
/// gerade dran ist (Richtung A). Darunter in beiden Fällen zwei kurze
/// Zeilengruppen: **Mein Team** und **Liga**.
///
/// Was dabei weggefallen ist: die 165 Punkte hohe Zustandskarte mit dem
/// halbtransparenten Dekor-Chevron (größte Fläche des Schirms für zwei
/// Wörter, und nicht antippbar), die Rubrik „Schnellzugriff" über zwei
/// gefüllten Kacheln, und die dritte Variante der Spielplan-Zeile.
class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafted = league.draftStatus != DraftStatus.setup;
    final draftFullyDone = league.draftStatus == DraftStatus.done;
    final seasonRunning = draftFullyDone;
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final openTrades = ref.watch(incomingTradeOffersProvider(league.id));
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;

    void go(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => screen));

    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 24),
      children: [
        // --- Kopf ----------------------------------------------------------
        if (seasonRunning && currentRound != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: MatchupHero(
              league: league,
              round: currentRound,
              fallback: _NaechsterSchritt(
                league: league,
                isAdmin: isAdmin,
                managerZahl: managers?.length,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _NaechsterSchritt(
              league: league,
              isAdmin: isAdmin,
              managerZahl: managers?.length,
            ),
          ),

        // Wochen-Recap (versteckt sich, bis es gewertete Punkte gibt).
        if (seasonRunning)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: WeeklyRecapCard(league: league),
          ),

        // --- Mein Team -----------------------------------------------------
        if (drafted) ...[
          const _Abschnittsmarke('Mein Team'),
          _LigaZeile(
            label: 'Aufstellung',
            onTap: () => go(LineupScreen(league: league)),
          ),
          const _Trenner(),
          _LigaZeile(
            label: 'Free Agency',
            onTap: () => go(FreeAgencyScreen(league: league)),
          ),
          const _Trenner(),
          _LigaZeile(
            label: 'Trades',
            zahl: openTrades,
            onTap: () => go(TradeScreen(league: league)),
          ),
        ],

        // --- Liga ----------------------------------------------------------
        const _Abschnittsmarke('Liga'),
        if (!draftFullyDone) ...[
          _LigaZeile(
            label: 'Draft-Raum',
            hinweis: switch (league.draftStatus) {
              DraftStatus.setup => 'noch nicht gestartet',
              DraftStatus.drafting => 'läuft',
              DraftStatus.done => null,
            },
            onTap: () => go(DraftRoomScreen(league: league)),
          ),
          const _Trenner(),
        ],
        // Ligainternes Tippspiel — nur wenn die Liga eines anbietet.
        if (league.tipEnabled ||
            ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull !=
                null) ...[
          _LeagueTipspielButton(league: league, isAdmin: isAdmin),
          const _Trenner(),
        ],
        _LigaZeile(
          label: 'Liga-Chat',
          onTap: () => go(FantasyChatScreen(league: league)),
        ),
        if (!draftFullyDone) ...[
          const _Trenner(),
          _LigaZeile(
            label: 'Spieler einladen',
            hinweis: managers == null ? null : '${managers.length} dabei',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvitePlayersScreen(league: league),
              ),
            ),
          ),
        ],

        // --- Spieltag ------------------------------------------------------
        _MatchdayFixtures(league: league),
      ],
    );
  }
}

/// Der eine Auftrag, der gerade dran ist — Kopf des Schirms in allen Phasen
/// ohne laufendes Duell.
///
/// Vorher stand hier eine Zustandsmeldung („Setup") in einer 165 Punkte hohen
/// Karte, die nicht antippbar war; was zu tun ist, steckte hinter einer Kachel
/// weiter unten. Ein Zustand ist kein Auftrag.
class _NaechsterSchritt extends ConsumerWidget {
  const _NaechsterSchritt({
    required this.league,
    required this.isAdmin,
    this.managerZahl,
  });

  final FantasyLeague league;
  final bool isAdmin;
  final int? managerZahl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final gold = const Color(0xFFFFC83D);

    void openRoom() => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DraftRoomScreen(league: league)),
    );

    final (String titel, String satz, String knopf, VoidCallback tun) =
        switch (league.draftStatus) {
          DraftStatus.setup =>
            league.maxTeams != null && managerZahl != null
                ? (
                    'Noch ${(league.maxTeams! - managerZahl!).clamp(0, 99)} Plätze frei',
                    'Lade Freunde ein — sobald alle da sind, startet der Draft.',
                    'Spieler einladen',
                    () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvitePlayersScreen(league: league),
              ),
            ),
                  )
                : (
                    'Die Liga steht',
                    'Lade Freunde ein und starte den Draft.',
                    'Spieler einladen',
                    () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InvitePlayersScreen(league: league),
              ),
            ),
                  ),
          DraftStatus.drafting => (
            league.mode == FantasyMode.dynasty
                ? 'Der ${league.draftPhase.label} läuft'
                : 'Der Draft läuft',
            'Wer an der Reihe ist, siehst du im Draft-Raum.',
            'Zum Draft',
            openRoom,
          ),
          DraftStatus.done => (
            'Die Saison läuft',
            'Stell deine Aufstellung, bevor der Spieltag anpfeift.',
            'Aufstellung',
            () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LineupScreen(league: league)),
            ),
          ),
        };

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(gold.withValues(alpha: 0.18), scheme.surface),
            Color.alphaBlend(gold.withValues(alpha: 0.05), scheme.surface),
          ],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.40), width: 0.8),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ALS NÄCHSTES',
            style: TextStyle(
              color: gold,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            titel,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            satz,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: tun,
                  style: FilledButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: scheme.surface,
                  ),
                  child: Text(knopf),
                ),
              ),
              // Den Draft startet nur der Ersteller — und nur, solange er
              // noch nicht läuft.
              if (isAdmin && league.draftStatus == DraftStatus.setup) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton(
                    onPressed: openRoom,
                    child: const Text('Draft starten'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Kapitelmarke wie im Live-, Favoriten- und Menü-Schirm.
class _Abschnittsmarke extends StatelessWidget {
  const _Abschnittsmarke(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.8,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _Trenner extends StatelessWidget {
  const _Trenner();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Container(
      height: 0.8,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
    ),
  );
}

/// Eine Zeile der Übersicht — ersetzt die gefüllten „Schnellzugriff"-Kacheln.
class _LigaZeile extends StatelessWidget {
  const _LigaZeile({
    required this.label,
    required this.onTap,
    this.hinweis,
    this.zahl = 0,
  });

  final String label;
  final VoidCallback onTap;

  /// Leiser Zusatz rechts („läuft", „3 dabei").
  final String? hinweis;

  /// Roter Zähler — etwas wartet auf dich.
  final int zahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: [label, ?hinweis, if (zahl > 0) '$zahl offen'].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hinweis != null)
                Text(
                  hinweis!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (zahl > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: MatchUpColors.red,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$zahl',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeagueTipspielButton extends ConsumerWidget {
  const _LeagueTipspielButton({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull;

    if (round != null) {
      return _TipTile(
        title: 'Tippspiel öffnen',
        onTap: () {
          activateRound(ref, round);
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
        },
      );
    }
    if (isAdmin) {
      return _TipTile(
        title: 'Ligainternes Tippspiel aktivieren',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CreateTipRoundScreen(
                  fantasyLeagueId: league.id,
                  initialName: league.name,
                ))),
      );
    }
    // Mitglied, aber noch nicht aktiviert.
    return const _TipTile(
      title: 'Ligainternes Tippspiel — noch nicht aktiviert',
    );
  }
}

/// Flache Zeile für den Ligainternen-Tippspiel-Button (gelber Akzent, ohne
/// Box, ohne Untertitel; deaktiviert = ausgegraut).
class _TipTile extends StatelessWidget {
  const _TipTile({required this.title, this.onTap});

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tile = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined, color: _cAmber),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            if (enabled)
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.55, child: tile);
  }
}

/// Auffälliger roter Zähler-Hinweis (z. B. offene Trade-Angebote).
class _NotifyBadge extends StatelessWidget {
  const _NotifyBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: _cRed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kader
// ---------------------------------------------------------------------------

/// Kader-Tab: oben der Aufstellungs-Editor, darunter die Aktionen
/// Free Agency (gelb), Trade (rot) und Spielersuche (grün).
class _RostersTab extends ConsumerWidget {
  const _RostersTab({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafted = league.draftStatus != DraftStatus.setup;
    if (!drafted) {
      return Stack(
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Die Kader entstehen im Draft — sobald er läuft, stellst du '
                'hier deine Elf auf, holst Free Agents und tradest.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DraftRoomScreen(league: league))),
              icon: const Icon(Icons.sports_esports),
              label: const Text('Zum Draft'),
            ),
          ),
        ],
      );
    }

    void open(Widget page) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => page));

    final myId = ref.watch(currentUserProvider)?.id;
    final roster = ref.watch(leagueRosterProvider(league.id)).valueOrNull ??
        const <RosterEntry>[];
    final myCount =
        myId == null ? 0 : rosterCountOf(myId, roster);
    final openTrades = ref.watch(incomingTradeOffersProvider(league.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        RosterLimitBanner(count: myCount, limit: league.roster.squadSize),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
          child: Row(
            children: [
              Expanded(
                child: _MiniAction(
                  label: 'Free Agency',
                  icon: Icons.person_add_alt,
                  color: _cAmber,
                  onTap: () => open(FreeAgencyScreen(league: league)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniAction(
                  label: 'Trade',
                  icon: Icons.swap_horiz,
                  color: _cRed,
                  badge: openTrades,
                  onTap: () => open(TradeScreen(league: league)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniAction(
                  label: 'Spielersuche',
                  icon: Icons.search,
                  color: _cGreen,
                  onTap: () => open(PlayerPoolScreen(league: league)),
                ),
              ),
            ],
          ),
        ),
        LineupEditor(league: league),
      ],
    );
  }
}

/// Große, farbige Aktions-Box (Kader-Tab).
/// Kompakte, farbige Aktions-Kachel (Kader-Tab, drei nebeneinander).
class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// Zahl für einen auffälligen Hinweis oben rechts (0 = kein Hinweis).
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: badge > 0
                    ? _cRed
                    : color.withValues(alpha: 0.40),
                width: badge > 0 ? 1.5 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: _cBase, size: 20),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -6,
                      right: -8,
                      child: _NotifyBadge(count: badge),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die Partien des aktuellen Spieltags, unten in der Übersicht.
///
/// Benutzt dieselbe Zeilenform wie Live- und Favoriten-Tab
/// (`fixturesWithDateHeaders`) statt einer eigenen Box mit eigener Anordnung.
/// Der Spielplan kommt hier als [Fixture] und wird dafür auf [TeamFixture]
/// gedreht — dieselben Felder, nur ein anderer Einstiegspunkt in dieselben
/// Daten. Drei Darstellungen derselben Liste waren zwei zu viel.
class _MatchdayFixtures extends ConsumerWidget {
  const _MatchdayFixtures({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final round = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final all = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (round == null || all == null) return const SizedBox.shrink();
    final fx = [
      for (final f in all)
        if (f.round == round) f,
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (fx.isEmpty) return const SizedBox.shrink();

    final liga = Leagues.byId(fx.first.leagueId);
    final umgewandelt = [
      for (final f in fx)
        TeamFixture(
          id: f.id,
          kickoff: f.kickoff,
          status: f.status,
          leagueName: liga.name,
          round: f.round,
          home: f.home,
          away: f.away,
          homeScore: f.homeScore,
          awayScore: f.awayScore,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Abschnittsmarke('$round. Spieltag'),
        ...fixturesWithDateHeaders(umgewandelt),
      ],
    );
  }
}
