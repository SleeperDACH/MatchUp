import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_league_screen.dart';
import '../features/fantasy/ui/fantasy_rank_chip.dart';
import '../features/friends/providers.dart';
import '../features/friends/ui/friends_screen.dart';
import '../features/leagues/providers.dart';
import '../features/leagues/ui/league_search_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/news/providers.dart';
import '../features/news/ui/transfers_screen.dart';
import '../features/news/ui/news_list_screen.dart';
import '../features/news/ui/news_tile.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/create_tip_round.dart';
import '../features/tippspiel/ui/tip_rank_chip.dart';
import 'league_screen.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets/matchup_chevron.dart';

/// Startbildschirm. Fantasy ist der Hauptfokus und steht oben; das
/// Tippspiel folgt als zweiter Bereich darunter.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final configured = AppConfig.isSupabaseConfigured;

    return Scaffold(
      // Seitenmenü (Profil · Freunde · Chats) über das Hamburger-Symbol.
      drawer: (configured && user != null) ? const _HomeMenuDrawer() : null,
      appBar: AppBar(
        centerTitle: true,
        // Hamburger oben links öffnet das schmale Seitenmenü.
        leading: (configured && user != null)
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menü',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
        title: const _MatchUpTitle(),
        actions: [
          // Öffentliche Ligasuche direkt neben dem Erstellen/Beitreten-Knopf.
          if (configured && user != null)
            IconButton(
              tooltip: 'Ligen entdecken',
              icon: const Icon(Icons.search, size: 25),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeagueSearchScreen())),
            ),
          // Erstellen & Beitreten zusammengefasst in einem Knopf oben rechts.
          if (configured && user != null)
            IconButton(
              tooltip: 'Erstellen oder beitreten',
              icon: const Icon(Icons.add_circle_outline, size: 27),
              onPressed: () => showCreateOrJoin(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myFantasyLeaguesProvider);
          ref.invalidate(myRoundsProvider);
        },
        child: ListView(
          // Unten extra Platz, damit der letzte Inhalt nicht unter der
          // schwebenden Glas-Navigationsleiste liegt.
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!configured)
              const _InfoCard(
                'Fantasy & Ligen brauchen eine Server-Verbindung. Starte die '
                'App über ./run_dev.sh (siehe README).',
              )
            else ...[
              const _Appear(child: _WelcomeHeader()),
              const SizedBox(height: 18),
              // Noch gar keine Liga (Fantasy + Tippspiel beide leer geladen):
              // statt zweier leerer Abschnitte ein großer Einstieg.
              if ((ref.watch(myFantasyLeaguesProvider).valueOrNull?.isEmpty ??
                      false) &&
                  (ref.watch(myRoundsProvider).valueOrNull?.isEmpty ?? false))
                const _Appear(delayMs: 80, child: _NoLeaguesHero())
              else ...[
                _Appear(
                  delayMs: 80,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _fantasySection(context, ref),
                  ),
                ),
                const SizedBox(height: 18),
                _Appear(
                  delayMs: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _tippspielSection(context, ref),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              const _Appear(delayMs: 220, child: _NewsSection()),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Fantasy (Hauptbereich)
  // ------------------------------------------------------------------
  List<Widget> _fantasySection(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myFantasyLeaguesProvider);
    return [
      _sectionHeader(context, 'Fantasy', Icons.shield_outlined,
          accent: MatchUpColors.green, count: leagues.valueOrNull?.length),
      leagues.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _InfoCard('Fantasy-Ligen konnten nicht geladen werden: $e'),
        data: (list) => list.isEmpty
            ? const _EmptyHint(
                'Noch keine Fantasy-Liga — oben rechts mit + eine Redraft- '
                'oder Dynasty-Liga erstellen.')
            : Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const _RowDivider(),
                    _FantasyLeagueCard(league: list[i]),
                  ],
                ],
              ),
      ),
    ];
  }

  // ------------------------------------------------------------------
  // Tippspiel (zweiter Bereich)
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    return [
      _sectionHeader(context, 'Tippspiel', Icons.emoji_events_outlined,
          accent: const Color(0xFFFFC83D), count: rounds.valueOrNull?.length),
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _InfoCard('Tipprunden konnten nicht geladen werden: $e'),
        data: (list) => list.isEmpty
            ? const _EmptyHint(
                'Noch keine Tipprunde — oben rechts mit + ein Tippspiel '
                'erstellen.')
            : Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const _RowDivider(),
                    _TipRoundCard(round: list[i]),
                  ],
                ],
              ),
      ),
    ];
  }

  Widget _sectionHeader(BuildContext context, String title, IconData icon,
      {Color? accent, int? count}) {
    final c = accent ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 4, 10),
      child: Row(
        children: [
          // Farbige Akzentleiste als Abschnitts-Marker.
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
                color: c, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9)),
              child: Text('$count',
                  style: TextStyle(
                      color: c, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Schmales Seitenmenü über das Hamburger-Symbol oben links (füllt den
/// Bildschirm nicht): Kopf mit Avatar + Name, darunter Profil, Freunde und
/// Chats als schnelle Direktzugänge.
class _HomeMenuDrawer extends ConsumerWidget {
  const _HomeMenuDrawer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final username = ref.watch(currentUsernameProvider).valueOrNull;
    final requests = ref.watch(incomingRequestsCountProvider);
    final unreadDms = ref.watch(hasUnreadDmsProvider);

    // Drawer schließen und dann das Ziel öffnen.
    void open(Widget screen) {
      Navigator.of(context).pop();
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      width: 264,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kopf: Avatar + Nutzername.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  AppAvatar(
                    imageUrl: profile?.avatarUrl,
                    emoji: profile?.avatarEmoji,
                    colorHex: profile?.avatarColor,
                    fallbackText: username,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      username ?? 'Profil',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.person_outline, color: scheme.primary),
              title: const Text('Profil'),
              onTap: () => open(const ProfileScreen()),
            ),
            ListTile(
              leading: Icon(Icons.group_outlined, color: scheme.primary),
              title: const Text('Freunde'),
              trailing: requests > 0
                  ? Badge.count(count: requests)
                  : null,
              onTap: () => open(const FriendsScreen()),
            ),
            ListTile(
              leading: Icon(Icons.forum_outlined, color: scheme.primary),
              title: const Text('Chats'),
              trailing: unreadDms
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: MatchUpColors.red, shape: BoxShape.circle),
                    )
                  : null,
              onTap: () => open(const ConversationsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bundesliga-News: Transferticker (Live-News) + Einstieg zu „Verletzungen &
/// Sperren". Der Transfer-Teil blendet sich aus, wenn (noch) keine News da
/// sind; der Ausfälle-Button ist immer erreichbar.
class _NewsSection extends ConsumerWidget {
  const _NewsSection();

  static const _maxTransfers = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final transfers = ref.watch(newsProvider('transfers'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(Icons.rss_feed, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text('Bundesliga aktuell',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        // Transferticker.
        transfers.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (items) {
            if (items.isEmpty) return const SizedBox.shrink();
            final shown = items.take(_maxTransfers).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: Row(
                    children: [
                      Icon(Icons.newspaper,
                          size: 15, color: const Color(0xFF5B9DF9)),
                      const SizedBox(width: 6),
                      Text('News',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  NewsTile(item: shown[i]),
                ],
                const SizedBox(height: 2),
                // Erweitern: vollständige, scrollbare Transfer-Liste.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NewsListScreen(
                                  topic: 'transfers',
                                  title: 'News',
                                  intro:
                                      'Aktuelle Bundesliga-Schlagzeilen, '
                                      'neueste zuerst. Tippen öffnet den '
                                      'Artikel.',
                                ))),
                    icon: const Icon(Icons.unfold_more, size: 18),
                    label: const Text('Ältere News anzeigen'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Einstieg, wenn noch gar keine Liga existiert: schlicht zwei Buttons
/// „Liga erstellen" und „Liga suchen" (ohne Überschrift/Beschreibung).
class _NoLeaguesHero extends ConsumerWidget {
  const _NoLeaguesHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Liga erstellen'),
            onPressed: () => showCreateOrJoin(context, ref),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('Liga suchen'),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueSearchScreen())),
          ),
        ),
      ],
    );
  }
}

/// Persönliche Begrüßung oben auf dem Home-Tab.
class _WelcomeHeader extends ConsumerWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final unreadCount = ref.watch(unreadDmCountProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18271D), MatchUpColors.base],
        ),
        border: Border.all(color: MatchUpColors.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name == null ? 'Willkommen ' : 'Hallo, $name ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                      ),
                    ),
                    const _WavingHand(size: 24),
                  ],
                ),
              ],
            ),
          ),
          // Schneller Zugang zu den Transfers (gelbes Transfer-Symbol).
          IconButton(
            tooltip: 'Transfers',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const TransfersScreen())),
            icon: const Icon(Icons.swap_horiz,
                size: 30, color: Color(0xFFFFC83D)),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Direktnachrichten',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ConversationsScreen())),
                icon: const Icon(Icons.forum_outlined,
                    size: 30, color: MatchUpColors.green),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: MatchUpColors.red,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: MatchUpColors.base, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dezenter Hinweis, wenn ein Bereich noch leer ist.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _FantasyLeagueCard extends ConsumerWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    // Offene Beitrittsanfragen nur für den Admin einer öffentlich–auf-Einladung-
    // Liga anzeigen (Live über Realtime).
    final showBadge =
        league.isPublic && league.isInviteOnly && myId == league.createdBy;
    final pending = showBadge
        ? (ref.watch(fantasyJoinRequestsProvider(league.id)).valueOrNull?.length ??
            0)
        : 0;
    return _LeagueTile(
      icon: league.mode == FantasyMode.dynasty
          ? Icons.auto_awesome
          : Icons.calendar_today,
      title: league.name,
      subtitle: league.mode.label,
      logoUrl: league.logoUrl,
      logoEmoji: league.logoEmoji,
      logoColor: league.logoColor,
      badge: pending,
      trailing: FantasyRankChip(league: league),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FantasyLeagueScreen(league: league))),
    );
  }
}

class _TipRoundCard extends ConsumerWidget {
  const _TipRoundCard({required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final league = Leagues.byId(round.leagueId);
    final icon = switch (league.id) {
      'wm2026' => Icons.public,
      'bundesliga' => Icons.sports_soccer,
      _ => Icons.emoji_events_outlined,
    };
    // Mehrere Wettbewerbe → „Bundesliga +2".
    final extra = round.competitions.length - 1;
    final subtitle = extra > 0 ? '${league.name} +$extra' : league.name;
    final myId = ref.watch(currentUserProvider)?.id;
    final showBadge =
        round.isPublic && round.isInviteOnly && myId == round.createdBy;
    final pending = showBadge
        ? (ref.watch(tipJoinRequestsProvider(round.id)).valueOrNull?.length ?? 0)
        : 0;
    return _LeagueTile(
      icon: icon,
      title: round.name,
      subtitle: subtitle,
      logoUrl: round.logoUrl,
      logoEmoji: round.logoEmoji,
      logoColor: round.logoColor,
      badge: pending,
      trailing: TipRankChip(round: round),
      onTap: () {
        activateRound(ref, round);
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
      },
    );
  }
}

/// Kleiner roter Zähler für offene Beitrittsanfragen (Home-Liga-Karte).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text('$count',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
    );
  }
}

/// Kompakte Liga-Zeile für den Homescreen (Fantasy & Tippspiel): kleine
/// Icon-Kachel, Name, Kontextzeile und rechts ein farbiger Status-Punkt
/// (statt eines Text-Chips) — dicht gereiht, aber als Karte erkennbar.
class _LeagueTile extends StatelessWidget {
  const _LeagueTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.logoUrl,
    this.logoEmoji,
    this.logoColor,
    this.trailing,
    this.badge = 0,
  });

  final IconData icon;
  final String title;

  /// Liga-Logo (Bild oder Emoji+Farbe); ohne beides greift das [icon].
  final String? logoUrl;
  final String? logoEmoji;
  final String? logoColor;

  /// Kleine graue Zeile: Modus (Redraft/Dynasty) bzw. Wettbewerb.
  final String subtitle;

  /// Optionaler Zusatz vor dem Chevron (z. B. Platzierungs-Chip).
  final Widget? trailing;

  /// Anzahl offener Beitrittsanfragen (nur Admin; 0 = kein Badge).
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Bewusst keine Card/Box: schlichte, randlose, dünne Listenzeile.
    return _PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
            child: Row(
              children: [
                AppAvatar(
                  imageUrl: logoUrl,
                  emoji: logoEmoji,
                  colorHex: logoColor,
                  fallbackIcon: icon,
                  size: 34,
                  cornerRadius: 9,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 8),
                  _CountBadge(count: badge),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
                const SizedBox(width: 10),
                // Nach rechts gedrehter MatchUp-Doppelchevron in Weiß.
                const RotatedBox(
                  quarterTurns: 1,
                  child: MatchUpChevron(size: 14, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dünner, eingerückter Trenner zwischen zwei Liga-Zeilen (ersetzt die
/// frühere Kasten-Optik der Cards).
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 49,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

/// Einmalige Einblend-Animation (Fade + leichtes Hochgleiten) beim Erscheinen;
/// mit [delayMs] gestaffelt für einen lebendigen Aufbau des Screens.
class _Appear extends StatefulWidget {
  const _Appear({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _t =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
            offset: Offset(0, (1 - _t.value) * 14), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Drückt sein Kind beim Antippen leicht zusammen (taktiles Feedback).
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});

  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // Listener beobachtet nur (verbraucht die Geste nicht) → InkWell-Ripple
    // und onTap des Kindes bleiben erhalten.
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Kleine, periodisch winkende Hand (👋) — Begrüßung im Kopfbereich.
class _WavingHand extends StatefulWidget {
  const _WavingHand({this.size = 24});

  final double size;

  @override
  State<_WavingHand> createState() => _WavingHandState();
}

class _WavingHandState extends State<_WavingHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2600))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // In der ersten Phase winken (Sinus), danach ruhen.
        final t = _c.value;
        final angle = t < 0.45 ? math.sin(t / 0.45 * math.pi * 3) * 0.35 : 0.0;
        return Transform.rotate(
            angle: angle, alignment: Alignment.bottomCenter, child: child);
      },
      child: Text('👋', style: TextStyle(fontSize: widget.size)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}


// ---------------------------------------------------------------------
// MatchUp-Wortmarke für die Kopfzeile: zweifarbiger Doppel-Chevron
// (links Green, rechts Red) + „Match"/„Up". Nativ nachgebaut nach dem
// Marken-SVG (assets/branding/matchup_logo_primary.svg), weil flutter_svg
// dessen Text-Element nicht rendert.
// ---------------------------------------------------------------------
class _MatchUpTitle extends StatelessWidget {
  const _MatchUpTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const MatchUpChevron(size: 22),
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: MatchUpColors.snow,
            ),
            children: const [
              TextSpan(text: 'Match'),
              TextSpan(
                  text: 'Up',
                  style: TextStyle(color: MatchUpColors.green)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Erstellen / Beitreten
// ---------------------------------------------------------------------

/// Fullscreen-Auswahl für den Erstellen-Knopf: zwei große farbige Felder
/// **Fantasy** und **Tippspiel**, darunter klein **Beitreten**. Der Screen gibt
/// nur die Wahl zurück; den jeweiligen Flow startet danach der Aufrufer.
void showCreateOrJoin(BuildContext context, WidgetRef ref) async {
  final choice = await Navigator.of(context).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const _CreateOrJoinScreen(),
  ));
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'fantasy':
      createFantasyLeagueFlow(context, FantasyMode.liga);
    case 'tip':
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateTipRoundScreen()));
    case 'join':
      joinAnyFlow(context, ref);
  }
}

class _CreateOrJoinScreen extends StatelessWidget {
  const _CreateOrJoinScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Liga erstellen')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Zwei große farbige Felder.
              Expanded(
                child: _CreateBigTile(
                  color: MatchUpColors.green,
                  image: 'assets/images/fantasy_bg.png',
                  title: 'Fantasy',
                  onTap: () => Navigator.of(context).pop('fantasy'),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _CreateBigTile(
                  color: const Color(0xFFFFC83D),
                  image: 'assets/images/tippspiel_bg.png',
                  title: 'Tippspiel',
                  onTap: () => Navigator.of(context).pop('tip'),
                ),
              ),
              const SizedBox(height: 18),
              // Beitreten – klein darunter.
              _CreateJoinTile(onTap: () => Navigator.of(context).pop('join')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Großes Auswahlfeld (Fantasy / Tippspiel) mit Bild-Hintergrund; ein dunkler
/// Verlauf unten hält den Titel gut lesbar.
class _CreateBigTile extends StatelessWidget {
  const _CreateBigTile({
    required this.color,
    required this.image,
    required this.title,
    required this.onTap,
  });

  final Color color;
  final String image;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border:
                  Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
              borderRadius: BorderRadius.circular(20),
              // Hochformatiges Motiv: oberen, spannenderen Bereich zeigen.
              image: DecorationImage(
                image: AssetImage(image),
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.55),
              ),
            ),
            child: Stack(
              children: [
                // Dunkler Verlauf unten für die Titel-Lesbarkeit.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          MatchUpColors.base.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
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

/// Kleineres „Beitreten"-Feld unter den großen Erstellen-Feldern.
class _CreateJoinTile extends StatelessWidget {
  const _CreateJoinTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.group_add_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Beitreten',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Text('Mit Einladungscode',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> joinAnyFlow(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Beitreten'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Gib den Einladungscode ein – für eine Fantasy-Liga '
              'oder eine Tipprunde.'),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Einladungscode',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Beitreten'),
        ),
      ],
    ),
  );
  if (code == null || code.trim().isEmpty) return;
  final trimmed = code.trim();

  // 1) Als Fantasy-Liga versuchen.
  try {
    final league =
        await ref.read(fantasyLeagueRepositoryProvider).joinLeague(trimmed);
    ref.invalidate(myFantasyLeaguesProvider);
    if (!context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FantasyLeagueScreen(league: league)));
    // Nach Draft-Start ist man nur „pending" — der Admin muss noch ein freies
    // Team zuweisen. Kurzer Hinweis, damit klar ist, warum kein Kader da ist.
    if (league.draftStatus != DraftStatus.setup && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Beigetreten! Der Draft läuft bereits — der Admin weist '
            'dir ein Team zu, sobald ein Platz frei ist.'),
      ));
    }
    return;
  } catch (e) {
    final msg = e.toString();
    if (!msg.contains('Ungültiger Einladungscode')) {
      // Der Code gehört zu einer Fantasy-Liga, der Beitritt scheiterte aber
      // aus einem anderen Grund (z. B. Draft bereits begonnen).
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg.contains('bereits begonnen')
            ? 'Der Draft dieser Liga hat bereits begonnen.'
            : 'Beitritt fehlgeschlagen: $e'),
      ));
      return;
    }
    // Sonst: kein Fantasy-Code -> als Tipprunde weiterversuchen.
  }

  // 2) Als Tipprunde versuchen.
  try {
    final round = await ref.read(tipRoundRepositoryProvider).joinRound(trimmed);
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg.contains('Ungültiger Einladungscode')
          ? 'Dieser Code passt zu keiner Fantasy-Liga und keiner Tipprunde.'
          : 'Beitritt fehlgeschlagen: $e'),
    ));
  }
}
