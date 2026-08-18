import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/ui/app_avatar.dart';
import '../core/ui/default_avatar.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/logic/league_status.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/draft_room_screen.dart';
import '../features/fantasy/ui/fantasy_league_screen.dart';
import '../features/fantasy/ui/fantasy_rank_chip.dart';
import '../features/friends/providers.dart';
import '../features/friends/ui/friends_screen.dart';
import '../features/leagues/providers.dart';
import '../features/leagues/ui/league_search_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/news/models/news_item.dart';
import '../features/news/providers.dart';
import '../features/news/ui/transfers_screen.dart';
import '../features/news/ui/news_list_screen.dart';
import '../features/news/ui/news_tile.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/create_tip_round.dart';
import '../features/tippspiel/ui/tip_rank_chip.dart';
import 'home_now.dart';
import 'impressum_screen.dart';
import 'league_screen.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets/matchup_chevron.dart';
import 'widgets/now_card.dart';
import 'widgets/pulsing_dot.dart';

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
              // Sollte im ausgelieferten Build nie erscheinen — die
              // Server-Adresse steckt seit dem TestFlight-Fehlschlag fest in
              // AppConfig. Bleibt als Auffangnetz für Builds, die sie per
              // --dart-define bewusst leeren. Deshalb kein Entwickler-Hinweis
              // mehr im Text: Beta-Tester können damit nichts anfangen.
              const _InfoCard(
                'Fantasy & Ligen brauchen eine Server-Verbindung. Diese '
                'App-Version wurde ohne Server ausgeliefert.',
              )
            else ...[
              const _Appear(child: _GreetingBar()),
              const SizedBox(height: 12),
              // Ganz oben das, was gerade ansteht — der Screen soll eine
              // Handlung anbieten, nicht nur eine Liste.
              const _Appear(delayMs: 40, child: _NowSection()),
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
  // Fantasy (Hauptbereich): quer zu wischende Karten. Bewusst eine andere
  // Form als das Tippspiel darunter und die News ganz unten — drei gleich
  // gebaute Listen untereinander waren der Grund, warum der Screen überall
  // gleich aussah.
  // ------------------------------------------------------------------
  List<Widget> _fantasySection(BuildContext context, WidgetRef ref) {
    final leagues = ref.watch(myFantasyLeaguesProvider);
    final list = leagues.valueOrNull;
    return [
      _sectionHeader(context, 'Meine Ligen', count: list?.length),
      if (leagues.hasError)
        _InfoCard('Fantasy-Ligen konnten nicht geladen werden: '
            '${leagues.error}')
      else if (list == null)
        const SizedBox(
          height: _kLeagueCardHeight,
          child: Center(child: CircularProgressIndicator()),
        )
      else
        _Bleed(
          hoehe: _kLeagueCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            physics: const BouncingScrollPhysics(),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => i < list.length
                ? _FantasyLeagueCard(league: list[i])
                : const _NewLeagueCard(),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Tippspiel (zweiter Bereich): schlanke Zeilen, keine Kacheln.
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    // Nur eigenständig erstellte Tipprunden. Ligainterne Tippspiele (an eine
    // Fantasy-Liga gekoppelt) erreicht man ausschließlich über die Liga.
    final standalone =
        rounds.valueOrNull?.where((r) => !r.isFantasyLinked).toList();
    return [
      _sectionHeader(context, 'Tippspiel', count: standalone?.length),
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _InfoCard('Tipprunden konnten nicht geladen werden: $e'),
        data: (_) => (standalone == null || standalone.isEmpty)
            ? const _CreateRow(
                text: 'Tippspiel anlegen',
                hint: 'Spieltage tippen, Punkte sammeln')
            : Column(
                children: [
                  for (var i = 0; i < standalone.length; i++) ...[
                    if (i > 0) const _RowDivider(),
                    _TipRoundCard(round: standalone[i]),
                  ],
                ],
              ),
      ),
    ];
  }

  /// Leichte Abschnittsüberschrift: kleine Versalien, Zähler, optional ein
  /// Link nach rechts. Vorher trug jeder Abschnitt denselben fetten Balken mit
  /// Symbol — drei gleiche Köpfe über drei gleichen Kästen.
  Widget _sectionHeader(BuildContext context, String title,
      {int? count, String? moreLabel, VoidCallback? onMore}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          if (count != null && count > 0) ...[
            const SizedBox(width: 8),
            Text('$count',
                style: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ],
          const Spacer(),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('${moreLabel ?? 'Alle'} ›',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
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
            const Spacer(),
            // Rechtliches, bewusst sehr dezent – nur der Vollständigkeit halber.
            // Der Datenschutz steht über dem Impressum, weil beide Stores ihn
            // verlangen und er häufiger gesucht wird.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(Uri.parse(AppConfig.privacyUrl),
                    mode: LaunchMode.externalApplication),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor:
                      scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                child: const Text('Datenschutz', style: TextStyle(fontSize: 10)),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => open(const ImpressumScreen()),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor:
                      scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                child: const Text('Impressum', style: TextStyle(fontSize: 10)),
              ),
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
/// Jetzt-Karte am Kopf des Screens. Lädt still im Hintergrund: solange nichts
/// feststeht (oder nichts ansteht), bleibt der Platz leer, statt einen
/// Ladeplatzhalter über den ganzen Screen zu schieben.
class _NowSection extends ConsumerWidget {
  const _NowSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(nowItemProvider).valueOrNull;
    if (item == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: NowCard(item: item, onOpen: () => _open(context, ref, item)),
    );
  }

  void _open(BuildContext context, WidgetRef ref, NowItem item) {
    final league = item.league;
    if (league != null) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DraftRoomScreen(league: league)));
      return;
    }
    final round = item.round;
    if (round == null) return;
    activateRound(ref, round);
    Navigator.of(context).push(MaterialPageRoute(
        // Direkt auf den Tippen-Tab: der Knopf verspricht genau das.
        builder: (_) => LeagueScreen(round: round, initialTab: 0)));
  }
}

/// News am Fuß des Screens. Bewusst klein gehalten: drei Schlagzeilen als
/// Ausblick, alles Weitere hinter „Alle". Früher standen hier fünf Meldungen
/// unter zwei Überschriften — das füllte die halbe Seite und drängte die
/// Ligen nach oben weg.
/// News ganz unten als schmale Querleiste — die dritte Form auf dem Screen
/// (Karten quer, Zeilen längs, Leiste). Früher standen hier fünf Meldungen
/// unter zwei Überschriften und füllten die halbe Seite.
class _NewsSection extends ConsumerWidget {
  const _NewsSection();

  static const _maxTransfers = 6;

  void _openList(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const NewsListScreen(
              topic: 'transfers',
              title: 'News',
              intro: 'Aktuelle Bundesliga-Schlagzeilen, neueste zuerst. '
                  'Tippen öffnet den Artikel.',
            )));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(newsProvider('transfers'));
    return transfers.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final shown = items.take(_maxTransfers).toList();
        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Row(
                children: [
                  Text('NEWS',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      )),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _openList(context),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text('Alle ›',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            _Bleed(
              hoehe: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                physics: const BouncingScrollPhysics(),
                itemCount: shown.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 9),
                itemBuilder: (_, i) => i < shown.length
                    ? _NewsCard(item: shown[i])
                    : _MoreNewsCard(onTap: () => _openList(context)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Eine Schlagzeile als schmale Karte der News-Leiste.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final NewsItem item;

  static const _blau = Color(0xFF5B9DF9);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (item.source != null) item.source!,
      if (item.publishedAt != null) relativeNewsTime(item.publishedAt!),
    ].join(' · ');
    return SizedBox(
      width: 232,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openNews(context, item.url),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, height: 1.15, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.newspaper, size: 12, color: _blau),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abschluss der News-Leiste: alles Weitere in der vollen Liste.
class _MoreNewsCard extends StatelessWidget {
  const _MoreNewsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.8)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_forward_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(height: 6),
                Text('Alle News',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
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
          height: 64,
          child: FilledButton.icon(
            icon: const Icon(Icons.add, size: 26),
            label: const Text('Liga erstellen',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            onPressed: () => showCreateOrJoin(context, ref),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('Liga suchen', style: TextStyle(fontSize: 16)),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LeagueSearchScreen())),
          ),
        ),
      ],
    );
  }
}

/// Persönliche Begrüßung oben auf dem Home-Tab.
/// Schlanke Kopfzeile: Gruß links, die beiden Direktzugänge rechts. Die
/// frühere Begrüßungskarte war ein Kasten mit Verlauf über den halben
/// Bildschirmkopf — viel Fläche für einen Namen. Der Platz gehört jetzt der
/// Jetzt-Karte direkt darunter.
class _GreetingBar extends ConsumerWidget {
  const _GreetingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final unreadCount = ref.watch(unreadDmCountProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Flexible(
            child: Text(
              name == null ? 'Willkommen' : 'Hallo, $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
            ),
          ),
          const SizedBox(width: 6),
          const _WavingHand(size: 20),
          const Spacer(),
          // Transfers (gelb) und Direktnachrichten (grün) bleiben als
          // Direktzugänge erhalten, nur ohne den Kasten drumherum.
          _HeaderAction(
            tooltip: 'Transfers',
            icon: Icons.swap_horiz,
            color: const Color(0xFFFFC83D),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TransfersScreen())),
          ),
          _HeaderAction(
            tooltip: 'Direktnachrichten',
            icon: Icons.forum_outlined,
            color: MatchUpColors.green,
            badge: unreadCount,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConversationsScreen())),
          ),
        ],
      ),
    );
  }
}

/// Kompakter Icon-Knopf der Kopfzeile, optional mit rotem Zähler.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(icon, size: 26, color: color),
        ),
        if (badge > 0)
          Positioned(
            right: 2,
            top: 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: MatchUpColors.red,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: Theme.of(context).colorScheme.surface, width: 2),
              ),
              child: Center(
                child: Text(
                  badge > 99 ? '99+' : '$badge',
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
    );
  }
}

/// Leerer Tippspiel-Abschnitt als antippbare Zeile statt als Satz: der
/// Hinweis „oben rechts mit +" ließ eine halbe Seite ungenutzt und war
/// obendrein nur eine Wegbeschreibung.
class _CreateRow extends ConsumerWidget {
  const _CreateRow({required this.text, required this.hint});

  final String text;
  final String hint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showCreateOrJoin(context, ref),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.8)),
            ),
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(text,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(hint,
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
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

/// Maße der Liga-Karten im Querlauf — auch für den Ladeplatz und die
/// „Neue Liga"-Karte, damit die Reihe nicht springt.
const double _kLeagueCardHeight = 168;
const double _kLeagueCardWidth = 186;

/// Eine Fantasy-Liga als Karte: eigene Farbe, eigener Zustand. Die Farbe
/// kommt deterministisch aus der Liga-ID (dieselbe Palette wie die Avatare),
/// solange die Liga kein eigenes Logo hat — vorher trugen alle Ligen dieselbe
/// Marke in nur zwei Typ-Farben und waren dadurch nicht auseinanderzuhalten.
class _FantasyLeagueCard extends ConsumerWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final myId = ref.watch(currentUserProvider)?.id;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final status = fantasyStatus(league, teams: managers?.length);
    final farbe = parseColor(league.logoColor) ?? defaultAvatarColor(league.id);

    // Offene Beitrittsanfragen nur für den Admin einer öffentlich–auf-
    // Einladung-Liga (Live über Realtime).
    final showBadge =
        league.isPublic && league.isInviteOnly && myId == league.createdBy;
    final pending = showBadge
        ? (ref.watch(fantasyJoinRequestsProvider(league.id)).valueOrNull?.length ??
            0)
        : 0;

    return _PressScale(
      child: SizedBox(
        width: _kLeagueCardWidth,
        height: _kLeagueCardHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FantasyLeagueScreen(league: league))),
            borderRadius: BorderRadius.circular(18),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                        farbe.withValues(alpha: dark ? 0.26 : 0.18),
                        scheme.surfaceContainerHighest),
                    Color.alphaBlend(
                        farbe.withValues(alpha: dark ? 0.06 : 0.05),
                        scheme.surfaceContainerHighest),
                  ],
                ),
                border: Border.all(color: farbe.withValues(alpha: 0.42)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LeagueMark(
                            league: league, farbe: farbe, size: 34),
                        const Spacer(),
                        if (pending > 0)
                          _CountBadge(count: pending)
                        else
                          _ModePill(mode: league.mode, farbe: farbe),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      league.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                    ),
                    const Spacer(),
                    if (managers != null && managers.isNotEmpty)
                      _ManagerRow(managers: managers),
                    const SizedBox(height: 6),
                    Divider(
                        height: 9,
                        thickness: 1,
                        color: farbe.withValues(alpha: 0.28)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                            child: _StatusLine(status: status, farbe: farbe)),
                        FantasyRankChip(league: league),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Liga-Zeichen: eigenes Logo, sonst die MatchUp-Marke in der Liga-Farbe.
class _LeagueMark extends StatelessWidget {
  const _LeagueMark(
      {required this.league, required this.farbe, required this.size});

  final FantasyLeague league;
  final Color farbe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasCustom = (league.logoUrl != null && league.logoUrl!.isNotEmpty) ||
        (league.logoEmoji != null && league.logoEmoji!.isNotEmpty);
    if (hasCustom) {
      return AppAvatar(
        imageUrl: league.logoUrl,
        emoji: league.logoEmoji,
        colorHex: league.logoColor,
        fallbackIcon: Icons.shield_outlined,
        size: size,
        cornerRadius: 10,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: farbe, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: MatchUpChevron(size: size * 0.5, color: MatchUpColors.base),
    );
  }
}

/// Überlappende Mitglieder-Avatare — füllt die Mitte der Karte mit etwas,
/// das jede Liga anders zeigt, statt mit Leerraum.
class _ManagerRow extends StatelessWidget {
  const _ManagerRow({required this.managers});

  final List<FantasyManager> managers;

  static const _max = 5;
  static const _size = 22.0;
  static const _overlap = 7.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gezeigt = managers.take(_max).toList();
    final rest = managers.length - gezeigt.length;
    return SizedBox(
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < gezeigt.length; i++)
            Positioned(
              left: i * (_size - _overlap),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                child: AppAvatar(
                  imageUrl: gezeigt[i].avatarUrl,
                  emoji: gezeigt[i].avatarEmoji,
                  colorHex: gezeigt[i].avatarColor,
                  fallbackText: gezeigt[i].username,
                  seed: gezeigt[i].userId,
                  size: _size,
                ),
              ),
            ),
          if (rest > 0)
            Positioned(
              left: gezeigt.length * (_size - _overlap) + 4,
              top: 3,
              child: Text('+$rest',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

/// Kleiner Typ-Anhänger („Redraft" / „Dynasty"). Trägt jetzt der Text, was
/// vorher die Farbe tragen musste — die gehört der Liga-Identität.
class _ModePill extends StatelessWidget {
  const _ModePill({required this.mode, required this.farbe});

  final FantasyMode mode;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: farbe.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        mode.label,
        style: TextStyle(
            color: farbe, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Zustandszeile der Liga-Karte: Punkt in der Ton-Farbe, Text, leise Zusatzzeile.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.farbe});

  final LeagueStatus status;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ton = switch (status.tone) {
      LeagueStatusTone.wartet => scheme.onSurfaceVariant,
      LeagueStatusTone.laeuft => MatchUpColors.green,
      LeagueStatusTone.bereit => farbe,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // Der laufende Draft ist das einzige, was wirklich tickt.
            if (status.tone == LeagueStatusTone.laeuft)
              PulsingDot(size: 7, color: ton)
            else
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: ton, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: ton, fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        if (status.detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 1),
            child: Text(status.detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: scheme.onSurfaceVariant, fontSize: 11)),
          ),
      ],
    );
  }
}

/// Letzte Karte der Reihe: neue Liga anlegen oder beitreten.
class _NewLeagueCard extends ConsumerWidget {
  const _NewLeagueCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: SizedBox(
        width: 116,
        height: _kLeagueCardHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showCreateOrJoin(context, ref),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.8)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      size: 28, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text('Liga',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text('anlegen',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
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
      // MatchUp-Marke in Gold für Tippspiele.
      brandColor: const Color(0xFFFFC83D),
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
    this.brandColor,
    this.trailing,
    this.badge = 0,
  });

  final IconData icon;
  final String title;

  /// Liga-Logo (Bild oder Emoji+Farbe); ohne beides greift die MatchUp-Marke
  /// in [brandColor] (klar unterscheidbar je Liga-Typ), sonst das [icon].
  final String? logoUrl;
  final String? logoEmoji;
  final String? logoColor;

  /// Typ-Farbe der MatchUp-Marke als Fallback (Tippspiel/Redraft/Dynasty).
  final Color? brandColor;

  /// Kleine graue Zeile: Modus (Redraft/Dynasty) bzw. Wettbewerb.
  final String subtitle;

  /// Optionaler Zusatz vor dem Chevron (z. B. Platzierungs-Chip).
  final Widget? trailing;

  /// Anzahl offener Beitrittsanfragen (nur Admin; 0 = kein Badge).
  final int badge;
  final VoidCallback onTap;

  /// Leading-Symbol: eigenes Liga-Logo, sonst die MatchUp-Marke in der
  /// Typ-Farbe (Tippspiel/Redraft/Dynasty), sonst Icon.
  Widget _leading(ColorScheme scheme) {
    final hasCustom = (logoUrl != null && logoUrl!.isNotEmpty) ||
        (logoEmoji != null && logoEmoji!.isNotEmpty);
    if (!hasCustom && brandColor != null) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: brandColor,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: MatchUpChevron(size: 17, color: MatchUpColors.base),
      );
    }
    return AppAvatar(
      imageUrl: logoUrl,
      emoji: logoEmoji,
      colorHex: logoColor,
      fallbackIcon: icon,
      size: 34,
      cornerRadius: 9,
    );
  }

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
                _leading(scheme),
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

/// Dünner, eingerückter Trenner zwischen zwei Tipprunden-Zeilen.
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

/// Lässt eine Querleiste über den Seitenrand hinauslaufen: der Seiten-
/// ListView hat 12 px Innenabstand, eine Kachelreihe soll aber bis an die
/// Bildschirmkante reichen, damit die angeschnittene Karte zeigt, dass es
/// weitergeht.
class _Bleed extends StatelessWidget {
  const _Bleed({required this.hoehe, required this.child});

  final double hoehe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final breite = MediaQuery.sizeOf(context).width;
    return SizedBox(
      height: hoehe,
      child: OverflowBox(
        minWidth: breite,
        maxWidth: breite,
        alignment: Alignment.center,
        child: child,
      ),
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
                  image: 'assets/images/fantasy_bg.jpg',
                  title: 'Fantasy',
                  onTap: () => Navigator.of(context).pop('fantasy'),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _CreateBigTile(
                  color: const Color(0xFFFFC83D),
                  image: 'assets/images/tippspiel_bg.jpg',
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
    const radius = BorderRadius.all(Radius.circular(20));
    return Container(
      width: double.infinity,
      // Rahmen als Vordergrund → liegt sauber (ohne Naht) über Bild & Ripple.
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: radius,
        child: Ink.image(
          image: AssetImage(image),
          fit: BoxFit.cover,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Dunkler Verlauf unten für die Titel-Lesbarkeit.
                DecoratedBox(
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
