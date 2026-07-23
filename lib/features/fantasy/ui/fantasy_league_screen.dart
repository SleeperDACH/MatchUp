import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/league_screen.dart';
import '../../../app/widgets/matchup_chevron.dart';
import '../../../app/widgets/vibrant_league_title.dart';
import '../../../core/models/models.dart';
import '../../auth/providers.dart';
import '../../leagues/providers.dart';
import '../../tippspiel/providers.dart';
import '../../tippspiel/ui/create_tip_round.dart';
import '../logic/fantasy_scoring_engine.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'club_badge.dart';
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
          // Feste Vier-Tab-Leiste (Icon + Label), alle auf einen Blick.
          bottom: const TabBar(
            labelPadding: EdgeInsets.zero,
            tabs: [
              Tab(
                  icon: Icon(Icons.dashboard_outlined, size: 20),
                  text: 'Übersicht'),
              Tab(icon: MatchUpChevron(size: 20), text: 'MatchUp'),
              Tab(icon: Icon(Icons.shield_outlined, size: 20), text: 'Kader'),
              Tab(
                  icon: Icon(Icons.leaderboard_outlined, size: 20),
                  text: 'Tabelle'),
            ],
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

// Akzentfarben für die Übersicht (MatchUp-Palette + abgestimmte Töne).
const _cGreen = Color(0xFF4ADE6A);
const _cTeal = Color(0xFF4FC3A1);
const _cAmber = Color(0xFFFFC83D);
const _cRed = Color(0xFFF23030);
const _cBlue = Color(0xFF5B9DF9);
const _cBase = Color(0xFF12141C);

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.league, required this.isAdmin});

  final FantasyLeague league;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafted = league.draftStatus != DraftStatus.setup;
    // Draft komplett durch: Redraft fertig oder Dynasty nach dem U20-Draft.
    // Dann wird der Draft-Raum nicht mehr gebraucht (bei Dynasty steht nach
    // dem Haupt-Draft noch der U20-Draft aus → Raum bleibt sichtbar).
    final draftFullyDone = league.draftStatus == DraftStatus.done &&
        (league.mode != FantasyMode.dynasty ||
            league.draftPhase == DraftPhase.u20);
    // „Saison läuft": Draft fertig und (bei Dynasty) der U20-Draft nicht mehr
    // ausstehend. In diesem Zustand ersetzt der Live-MatchUp den Status-Kopf.
    final seasonRunning = league.draftStatus == DraftStatus.done &&
        !(league.mode == FantasyMode.dynasty &&
            league.draftPhase == DraftPhase.startup);
    final labelStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurfaceVariant);
    final action = _draftAction(context, ref, league, isAdmin);
    final currentRound = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final openTrades = ref.watch(incomingTradeOffersProvider(league.id));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (seasonRunning && currentRound != null)
          MatchupHero(
            league: league,
            round: currentRound,
            fallback: _StatusHero(league: league),
          )
        else
          _StatusHero(league: league),
        if (action != null) ...[
          const SizedBox(height: 14),
          action,
        ],
        const SizedBox(height: 24),
        // Wochen-Recap (versteckt sich, bis es gewertete Punkte gibt).
        if (seasonRunning) WeeklyRecapCard(league: league),
        // Spieler einladen: über die eigenen Chats/Freunde eine Beitreten-
        // Einladung verschicken — nur solange der Draft noch nicht durch ist.
        if (!draftFullyDone) ...[
          _InvitePlayersButton(league: league),
          const SizedBox(height: 12),
        ],
        // Ligainternes Tippspiel (über dem Schnellzugriff) — nur wenn die Liga
        // ein Tippspiel anbietet bzw. schon eines aktiviert ist.
        if (league.tipEnabled ||
            ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull !=
                null) ...[
          _LeagueTipspielButton(league: league, isAdmin: isAdmin),
          const SizedBox(height: 20),
        ],
        Text('Schnellzugriff', style: labelStyle),
        const SizedBox(height: 14),
        // Randlose Icon-Aktionen (farbige Kreise statt gefüllter Kästen),
        // gleichmäßig in einer Reihe verteilt.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (drafted) ...[
              Expanded(
                child: _QuickAction(
                  icon: Icons.sports_soccer,
                  label: 'Aufstellung',
                  color: _cTeal,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => LineupScreen(league: league))),
                ),
              ),
              Expanded(
                child: _QuickAction(
                  icon: Icons.person_add_alt,
                  label: 'Free Agency',
                  color: _cAmber,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => FreeAgencyScreen(league: league))),
                ),
              ),
              Expanded(
                child: _QuickAction(
                  icon: Icons.swap_horiz,
                  label: 'Trade',
                  color: _cRed,
                  badge: openTrades,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => TradeScreen(league: league))),
                ),
              ),
            ],
            if (!draftFullyDone)
              Expanded(
                child: _QuickAction(
                  icon: Icons.meeting_room_outlined,
                  label: 'Draft-Raum',
                  color: _cBlue,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DraftRoomScreen(league: league))),
                ),
              ),
            Expanded(
              child: _QuickAction(
                icon: Icons.forum_outlined,
                label: 'Liga-Chat',
                color: _cGreen,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FantasyChatScreen(league: league))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _MatchdayFixtures(league: league),
      ],
    );
  }

  /// Primäre Draft-Aktion für den aktuellen Zustand — oder `null`, wenn es
  /// gerade nichts zu tun gibt (dann führt das „Draft-Raum"-Tile in den Raum,
  /// wo auch der Warte-Hinweis steht).
  Widget? _draftAction(
      BuildContext context, WidgetRef ref, FantasyLeague live, bool isAdmin) {
    void openRoom() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DraftRoomScreen(league: live)));

    Future<void> run(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        await action();
        ref.invalidate(fantasyManagersProvider(live.id));
        ref.invalidate(draftLeagueProvider(live.id));
        navigator.push(
            MaterialPageRoute(builder: (_) => DraftRoomScreen(league: live)));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Fehlgeschlagen: $e')));
      }
    }

    final dynasty = live.mode == FantasyMode.dynasty;
    final repo = ref.read(draftRepositoryProvider);

    switch (live.draftStatus) {
      case DraftStatus.setup:
        // Kein eigener Button mehr — der Einstieg läuft über die
        // „Draft-Raum"-Kachel; dort startet der Admin auch den Draft.
        return null;
      case DraftStatus.drafting:
        return FilledButton.icon(
          icon: const Icon(Icons.sports),
          label: Text(dynasty ? 'Zum ${live.draftPhase.label}' : 'Zum Draft'),
          onPressed: openRoom,
        );
      case DraftStatus.done:
        if (dynasty && live.draftPhase == DraftPhase.startup && isAdmin) {
          return FilledButton.icon(
            icon: const Icon(Icons.auto_awesome),
            label: const Text('U20-Draft starten'),
            onPressed: () => run(() => repo.startU20Draft(live.id)),
          );
        }
        return null;
    }
  }
}

/// Farbiger Status-Kopf: zeigt die aktuelle Phase der Liga mit Akzentfarbe.
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.league});

  final FantasyLeague league;

  ({Color color, IconData icon, String title, String subtitle}) _info() {
    switch (league.draftStatus) {
      case DraftStatus.setup:
        return (
          color: _cAmber,
          icon: Icons.hourglass_top,
          title: 'Setup',
          subtitle: 'Lade Freunde ein und starte den Draft.'
        );
      case DraftStatus.drafting:
        return (
          color: _cGreen,
          icon: Icons.sports,
          title: 'Draft läuft',
          subtitle: 'Der Draft ist gerade im Gange.'
        );
      case DraftStatus.done:
        if (league.mode == FantasyMode.dynasty &&
            league.draftPhase == DraftPhase.startup) {
          return (
            color: _cTeal,
            icon: Icons.auto_awesome,
            title: 'Haupt-Draft beendet',
            subtitle: 'Als Nächstes steht der U20-Draft an.'
          );
        }
        return (
          color: _cGreen,
          icon: Icons.emoji_events,
          title: 'Saison läuft',
          subtitle: 'Stell deine Elf auf und sammle Punkte.'
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _info();
    return Container(
      constraints: const BoxConstraints(minHeight: 170),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [i.color.withValues(alpha: 0.38), _cBase],
        ),
        border: Border.all(color: i.color.withValues(alpha: 0.45)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            heroWatermark(),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: Row(
                  children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: i.color, shape: BoxShape.circle),
            child: Icon(i.icon, color: _cBase, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(i.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75))),
              ],
            ),
          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Farbige Kennzahl-Pille (Teilnehmer / Kadergröße / Startelf).
/// Farbige Aktions-Kachel im Schnellzugriff-Raster.
/// Randlose Schnellzugriff-Aktion: farbiger Icon-Kreis + Label darunter,
/// ohne getönte Box. Optionaler Zähler-Hinweis (z. B. offene Trades).
/// Auffälliger „Spieler einladen"-Button auf der Übersicht: öffnet die
/// Chat-/Freunde-Auswahl und verschickt eine Beitreten-Einladung. Liegen
/// Beitrittsanfragen vor (öffentlich–auf Einladung), zeigt der Button einen
/// Badge und führt zu deren Bearbeitung.
/// Ligainternes Tippspiel: aktiviert (alle öffnen), noch nicht aktiviert
/// (Admin aktiviert; Mitglieder sehen einen ausgegrauten Hinweis).
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
        subtitle: 'Ligainternes Tippspiel — tippen, Tabelle, Chat',
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
        subtitle: 'Fantasy + Tippspiel mit denselben Mitgliedern',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CreateTipRoundScreen(
                  fantasyLeagueId: league.id,
                  initialName: league.name,
                ))),
      );
    }
    // Mitglied, aber noch nicht aktiviert.
    return const _TipTile(
      title: 'Ligainternes Tippspiel',
      subtitle: 'Noch nicht aktiviert',
      onTap: null,
    );
  }
}

/// Kachel für den Ligainternen-Tippspiel-Button (gelber Akzent; deaktiviert =
/// ausgegraut).
class _TipTile extends StatelessWidget {
  const _TipTile({required this.title, required this.subtitle, this.onTap});

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final tile = Material(
      color: _cAmber.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, color: _cAmber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (enabled)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
    return enabled ? tile : Opacity(opacity: 0.55, child: tile);
  }
}

class _InvitePlayersButton extends ConsumerWidget {
  const _InvitePlayersButton({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final myId = ref.watch(currentUserProvider)?.id;
    final pending = (league.isPublic &&
            league.isInviteOnly &&
            myId == league.createdBy)
        ? (ref.watch(fantasyJoinRequestsProvider(league.id)).valueOrNull?.length ??
            0)
        : 0;
    final subtitle = pending > 0
        ? '$pending offene Anfrage${pending == 1 ? '' : 'n'} · Chats & Freunde einladen'
        : 'Über deine Chats & Freunde zur Liga einladen';

    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => InvitePlayersScreen(league: league))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.person_add_alt_1, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Spieler einladen',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (pending > 0) ...[
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text('$pending',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: scheme.onError,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap,
      this.badge = 0});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Zahl für einen auffälligen Hinweis oben rechts (0 = kein Hinweis).
  final int badge;

  @override
  Widget build(BuildContext context) {
    // Getönte Karte in der Aktionsfarbe — füllt die Reihe und wirkt lebendiger
    // als ein freistehendes Icon.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.22),
            color.withValues(alpha: 0.07),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: color.withValues(alpha: 0.45),
                              blurRadius: 10,
                              spreadRadius: -2),
                        ],
                      ),
                      child: Icon(icon, color: _cBase, size: 24),
                    ),
                    if (badge > 0)
                      Positioned(
                        top: -5,
                        right: -7,
                        child: _NotifyBadge(count: badge),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.15)),
              ],
            ),
          ),
        ),
      ),
    );
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

/// Zeigt die Partien des aktuellen Spieltags (unten in der Übersicht):
/// Anstoßzeit bzw. Ergebnis je Spiel.
class _MatchdayFixtures extends ConsumerWidget {
  const _MatchdayFixtures({required this.league});

  final FantasyLeague league;

  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final round = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
    final all = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
    if (round == null || all == null) return const SizedBox.shrink();
    final fx = [
      for (final f in all)
        if (f.round == round) f
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    if (fx.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.stadium_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Text('Spieltag $round',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (final (i, f) in fx.indexed) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      color: scheme.outlineVariant.withValues(alpha: 0.5)),
                _row(context, f),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, Fixture f) {
    final scheme = Theme.of(context).colorScheme;
    final hasScore = f.homeScore != null && f.awayScore != null;
    final live = f.status == FixtureStatus.live;

    Widget mid;
    if (hasScore) {
      mid = Text('${f.homeScore} : ${f.awayScore}',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: live ? scheme.error : scheme.onSurface));
    } else {
      final k = f.kickoff.toLocal();
      final wd = _weekdays[k.weekday - 1];
      final dd = k.day.toString().padLeft(2, '0');
      final mo = k.month.toString().padLeft(2, '0');
      final hh = k.hour.toString().padLeft(2, '0');
      final mm = k.minute.toString().padLeft(2, '0');
      // Wochentag + Datum oben, Uhrzeit darunter.
      mid = Text('$wd $dd.$mo.\n$hh:$mm',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: scheme.onSurfaceVariant, height: 1.25));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(f.home.shortName,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                ClubBadge(
                    club: f.home.name, iconUrl: f.home.iconUrl, size: 22),
              ],
            ),
          ),
          SizedBox(width: 66, child: Center(child: mid)),
          Expanded(
            child: Row(
              children: [
                ClubBadge(
                    club: f.away.name, iconUrl: f.away.iconUrl, size: 22),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(f.away.shortName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
