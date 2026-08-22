import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/models/team_fixture.dart';
import '../core/ui/app_avatar.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/logic/draft_order.dart';
import '../features/fantasy/logic/league_status.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_league_screen.dart';
import '../features/fantasy/ui/league_colors.dart';
import '../features/leagues/providers.dart';
import '../features/leagues/ui/join_by_code.dart';
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
import '../features/tippspiel/ui/team_badge.dart';
import 'home_favorites.dart';
import 'home_menu_drawer.dart';
import 'home_tip_status.dart';
import 'league_screen.dart';
import 'match_detail_screen.dart';
import 'theme.dart';
import 'widgets/league_logo.dart';
import 'widgets/matchup_chevron.dart';
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
      drawer: (configured && user != null) ? const HomeMenuDrawer() : null,
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
              const SizedBox(height: 16),
              // Noch gar keine Liga (Fantasy + Tippspiel beide leer geladen):
              // statt zweier leerer Abschnitte ein großer Einstieg.
              if (_beideLeer(ref))
                const _Appear(delayMs: 80, child: _NoLeaguesHero())
              else ...[
                // Der Abschnitt mit Inhalt steht oben. Wer nur ein Tippspiel
                // hat, sah sonst zuerst eine leere Ligareihe, in der nur die
                // große „+"-Karte stand.
                for (final abschnitt in _tippspielZuerst(ref)
                    ? [_tippspielSection(context, ref), _fantasySection(context, ref)]
                    : [_fantasySection(context, ref), _tippspielSection(context, ref)]) ...[
                  _Appear(
                    delayMs: 80,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: abschnitt,
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
              // Die Abschnitte bringen ihren Abstand schon mit.
              const SizedBox(height: 4),
              const _Appear(delayMs: 190, child: _FavoritenSpiele()),
              const _Appear(delayMs: 220, child: _NewsSection()),
            ],
          ],
        ),
      ),
    );
  }

  /// Eigenständige Tipprunden. Ligainterne Tippspiele (an eine Fantasy-Liga
  /// gekoppelt) erreicht man ausschließlich über die Liga; `null` = lädt noch.
  List<TipRound>? _standaloneRounds(WidgetRef ref) => ref
      .watch(myRoundsProvider)
      .valueOrNull
      ?.where((r) => !r.isFantasyLinked)
      .toList();

  bool _beideLeer(WidgetRef ref) =>
      (ref.watch(myFantasyLeaguesProvider).valueOrNull?.isEmpty ?? false) &&
      (_standaloneRounds(ref)?.isEmpty ?? false);

  /// Nur ein Tippspiel, keine Fantasy-Liga → Tippspiel nach oben.
  bool _tippspielZuerst(WidgetRef ref) =>
      (ref.watch(myFantasyLeaguesProvider).valueOrNull?.isEmpty ?? false) &&
      (_standaloneRounds(ref)?.isNotEmpty ?? false);

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
      else if (list.isEmpty)
        // Ohne eine einzige Liga wäre die Querreihe nur eine große leere
        // „+"-Karte — als Zeile nimmt der Einstieg ein Sechstel des Platzes.
        const _CreateRow(
            text: 'Fantasy-Liga anlegen',
            hint: 'Draften, Kader managen, Saison spielen')
      else
        _Bleed(
          hoehe: _kLeagueCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: _kLeagueRowPad),
            physics: const BouncingScrollPhysics(),
            itemCount: list.length + 1,
            separatorBuilder: (_, _) =>
                const SizedBox(width: _kLeagueCardGap),
            itemBuilder: (_, i) => i < list.length
                ? _FantasyLeagueCard(league: list[i])
                : const _NewEntryCard(
                    label: 'Liga', hoehe: _kLeagueCardHeight),
          ),
        ),
    ];
  }

  // ------------------------------------------------------------------
  // Tippspiel: dieselbe Kartenform wie die Ligen, nur flacher — es ist der
  // zweite Bereich, nicht der Hauptbereich.
  // ------------------------------------------------------------------
  List<Widget> _tippspielSection(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider);
    final standalone = _standaloneRounds(ref);
    return [
      _sectionHeader(context, 'Tippspiel', count: standalone?.length),
      if (rounds.hasError)
        _InfoCard('Tipprunden konnten nicht geladen werden: ${rounds.error}')
      else if (standalone == null)
        const SizedBox(
          height: _kTipCardHeight,
          child: Center(child: CircularProgressIndicator()),
        )
      else if (standalone.isEmpty)
        const _CreateRow(
            text: 'Tippspiel anlegen',
            hint: 'Spieltage tippen, Punkte sammeln')
      else
        _Bleed(
          hoehe: _kTipCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _kLeagueRowPad),
            physics: const BouncingScrollPhysics(),
            itemCount: standalone.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: _kLeagueCardGap),
            itemBuilder: (_, i) => i < standalone.length
                ? _TipRoundCard(round: standalone[i])
                : const _NewEntryCard(
                    label: 'Tippspiel', hoehe: _kTipCardHeight),
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

/// Bundesliga-News: Transferticker (Live-News) + Einstieg zu „Verletzungen &
/// Sperren". Der Transfer-Teil blendet sich aus, wenn (noch) keine News da
/// sind; der Ausfälle-Button ist immer erreichbar.
/// Nächste Spiele der favorisierten Vereine — zwischen den eigenen Ligen und
/// den News. Es ist die einzige Stelle auf dem Screen, an der es um Fußball
/// statt um die eigenen Runden geht; deshalb steht sie hinter den Ligen und
/// vor den News.
///
/// Gezeigt wird der **Tag** des nächsten Spiels mit allen Partien darauf: an
/// einem Bundesliga-Samstag will man nicht nur den 15:30-Anstoß sehen.
class _FavoritenSpiele extends ConsumerWidget {
  const _FavoritenSpiele();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spiele = ref.watch(favoritenSpieleProvider).valueOrNull;
    // Ohne Favoriten (oder solange nichts geladen ist) bleibt der Abschnitt
    // weg — eine leere Überschrift wäre schlechter als gar keine.
    if (spiele == null || spiele.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tag = spiele.first.kickoff.toLocal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(
              children: [
                Text('MEINE VEREINE',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    )),
                const Spacer(),
                Text(
                  DateFormat('EEEE, d. MMM', 'de_DE').format(tag),
                  style: TextStyle(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < spiele.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        color:
                            scheme.outlineVariant.withValues(alpha: 0.6)),
                  _FavoritSpielZeile(fixture: spiele[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Eine Partie: Wettbewerbslogo, beide Wappen, beide Kurznamen, rechts die
/// Anstoßzeit. Das Wettbewerbslogo ist nicht Zierde — am selben Tag können
/// Pokal und Liga nebeneinander stehen, und zwei Vereine desselben Klubs
/// (Profis und zweite Mannschaft) tragen denselben Kurznamen.
class _FavoritSpielZeile extends StatelessWidget {
  const _FavoritSpielZeile({required this.fixture});

  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(fixtureId: fixture.id))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: LeagueLogo(
                    logoUrl: fixture.leagueLogo,
                    name: fixture.leagueName,
                    size: 16),
              ),
              const SizedBox(width: 8),
              TeamBadge(team: fixture.home, size: 20),
              const SizedBox(width: 7),
              // Ausgeschriebene Namen: die Kurzformen („ENE", „HAN") sagen
              // ohne Tabellenkontext wenig. Zwei Zeilen erlaubt, damit
              // „Borussia Mönchengladbach" nicht zu „Borussia M…" wird.
              Expanded(
                child: Text(fixture.home.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, height: 1.1)),
              ),
              // Anstoßzeit mittig zwischen beiden Mannschaften.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  DateFormat('HH:mm', 'de_DE').format(fixture.kickoff.toLocal()),
                  style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(
                child: Text(fixture.away.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, height: 1.1)),
              ),
              const SizedBox(width: 7),
              TeamBadge(team: fixture.away, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

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

/// Fuß einer Liga- oder Tipprunden-Karte: der Zustand sitzt in einer eigenen,
/// abgesetzten Leiste in der Kartenfarbe.
///
/// Vorher trennte eine dünne Linie den Zustand vom Rest, und Name samt
/// Untertitel schwebten mit viel totem Raum in der Kartenmitte. Die Leiste
/// gibt der Karte einen Boden: oben Marke und Name, unten der Zustand — was
/// zu tun ist, steht immer an derselben Stelle, auch wenn der Name zwei
/// Zeilen braucht.
class _KartenSockel extends StatelessWidget {
  const _KartenSockel({required this.farbe, required this.child});

  final Color farbe;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: farbe.withValues(alpha: 0.20),
          // 15, nicht 16: innen am 1px-Rahmen entlang, sonst blitzt in den
          // unteren Ecken die Kartenfläche durch.
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(15),
            bottomRight: Radius.circular(15),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 5, 8, 5),
          child: child,
        ),
      );
}

/// Höhe der Liga-Karten im Querlauf — auch für den Ladeplatz und die
/// „Neue Liga"-Karte, damit die Reihe nicht springt.
const double _kLeagueCardHeight = 132;

/// Höhe der Tipprunden-Karten: flacher als eine Liga-Karte, weil sie nur
/// Name und Wettbewerb trägt — und weil Tippspiel der zweite Bereich ist.
const double _kTipCardHeight = 126;

/// Marken-Gold des Tippspiels (Fallback, wenn die Runde kein Logo hat).
const Color _kTipGold = Color(0xFFFFC83D);

/// Abstand zwischen zwei Karten der Reihe.
const double _kLeagueCardGap = 8;

/// Seitlicher Innenabstand der Reihe (passend zum Seitenrand).
const double _kLeagueRowPad = 12;

/// Verlauf einer Kachel in ihrer Farbe.
///
/// Gemischt wird gegen den **Seitengrund**, nicht gegen die graue
/// Kartenfläche: 28 % Markengrün über einem blaustichigen Grau ergaben ein
/// stumpfes Salbeigrün — die Farbe sah blass aus, obwohl es dieselbe war.
/// Über dem fast schwarzen Grund bleibt der Farbton erhalten, und mit dem
/// höheren Anteil kommt er auch durch.
LinearGradient kartenVerlauf(Color farbe, ColorScheme scheme, bool dark) =>
    LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
            farbe.withValues(alpha: dark ? 0.50 : 0.26), scheme.surface),
        Color.alphaBlend(
            farbe.withValues(alpha: dark ? 0.14 : 0.07), scheme.surface),
      ],
    );

/// Kartenbreite so, dass **genau vier** nebeneinander auf den Schirm passen;
/// ab der fünften wird gewischt. Deshalb aus der Bildschirmbreite gerechnet
/// statt fest verdrahtet — auf einem kleinen iPhone wären vier feste 186er
/// nur zweieinhalb.
double leagueCardWidth(BuildContext context) {
  final frei = MediaQuery.sizeOf(context).width -
      2 * _kLeagueRowPad -
      3 * _kLeagueCardGap;
  return frei / 4;
}

/// Eine Fantasy-Liga als schmale Karte: eigene Farbe, eigener Zustand.
/// Die Farbe kommt deterministisch aus der Liga-ID — aber aus der Palette
/// ihres Modus, damit Redraft (kühl) und Dynasty (warm) auf einen Blick
/// auseinanderzuhalten sind. Vorher trugen alle Ligen dieselbe Marke in nur
/// zwei Typ-Farben und waren dadurch gar nicht zu unterscheiden.
class _FantasyLeagueCard extends ConsumerWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final myId = ref.watch(currentUserProvider)?.id;
    final managers = ref.watch(fantasyManagersProvider(league.id)).valueOrNull;
    final status = _draftGeschaerft(
      fantasyStatus(league, teams: managers?.length),
      league,
      managers,
      myId,
    );
    final farbe = parseColor(league.logoColor) ?? leagueColor(league.mode);

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
        width: leagueCardWidth(context),
        height: _kLeagueCardHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FantasyLeagueScreen(league: league))),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: kartenVerlauf(farbe, scheme, dark),
                border: Border.all(color: farbe.withValues(alpha: 0.65)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 9, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _LeagueMark(
                                  league: league, farbe: farbe, size: 26),
                              const Spacer(),
                              if (pending > 0) _CountBadge(count: pending),
                            ],
                          ),
                          // Der Zwischenraum liegt **über** dem Namen: so
                          // sitzt der Text am Sockel statt in der Mitte zu
                          // schweben, und eine zweite Namenszeile wächst nach
                          // oben in den freien Platz.
                          const Spacer(),
                          Flexible(
                            child: Text(
                              league.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05),
                            ),
                          ),
                          // Modus als Wort, weil die Farbe allein nur die
                          // Familie verrät, nicht den Namen. Bewusst **nicht**
                          // in der Kartenfarbe: seit der Verlauf kräftig ist,
                          // wäre Grün auf Grün kaum zu lesen. Und leiser als
                          // der Name — sonst sind beide Zeilen gleich laut.
                          Text(
                            league.mode.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 7),
                        ],
                      ),
                    ),
                  ),
                  _KartenSockel(
                    farbe: farbe,
                    child: _LigaStatusZeile(
                        league: league, status: status, farbe: farbe),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schärft den Draft-Zustand für die Karte nach: **wer** dran ist und **bis
/// wann**. Beides steht nicht in [fantasyStatus] — die Logik dort kennt nur
/// die Liga, nicht den angemeldeten Nutzer, und soll ohne Uhrzeit-Format
/// auskommen.
LeagueStatus _draftGeschaerft(LeagueStatus status, FantasyLeague league,
    List<FantasyManager>? managers, String? myId) {
  if (league.draftStatus != DraftStatus.drafting) return status;
  final dran = managers == null
      ? null
      : currentManager(managers, league.picksMade)?.userId;
  final frist = league.currentPickDeadline?.toLocal();
  return LeagueStatus(
    dran != null && dran == myId ? 'Du bist dran' : status.label,
    detail: [
      if (status.detail != null) status.detail!,
      if (frist != null) kurzeFrist(frist, DateTime.now()),
    ].join(' · '),
    tone: status.tone,
  );
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

/// Fußzeile der Liga-Karte. Läuft ein Draft, gewinnt der — seine Uhr tickt in
/// Minuten. Sonst zeigt die Karte, was im **ligainternen Tippspiel** offen
/// ist: dessen Runde taucht im Tippspiel-Abschnitt bewusst nicht auf (man
/// erreicht sie über die Liga), ihre offenen Tipps hätten sonst nirgends
/// mehr Platz. Ist auch dort nichts offen, bleibt es beim Liga-Zustand.
class _LigaStatusZeile extends ConsumerWidget {
  const _LigaStatusZeile(
      {required this.league, required this.status, required this.farbe});

  final FantasyLeague league;
  final LeagueStatus status;
  final Color farbe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (league.draftStatus == DraftStatus.drafting) {
      return _StatusLine(status: status, farbe: farbe);
    }
    // Läuft die Saison, ist der Tabellenplatz die Auskunft, die zählt —
    // „Kader steht" sagt dann nichts mehr. Vor dem ersten gewerteten
    // Spieltag gibt es keinen Platz; dann bleibt es beim Zustand.
    final platz = ref.watch(myFantasyRankProvider(league.id));
    if (platz != null) {
      return _StatusZeile(
        label: 'Platz ${platz.rank}',
        detail: 'von ${platz.total}',
        ton: platz.rank == 1 ? const Color(0xFFFFC83D) : MatchUpColors.green,
        pulsiert: false,
      );
    }
    final runde = ref.watch(fantasyTipRoundProvider(league.id)).valueOrNull;
    if (runde == null) return _StatusLine(status: status, farbe: farbe);
    final offen = ref.watch(offeneTippsProvider(runde.id)).valueOrNull;
    if (offen == null || offen.anzahl == 0) {
      return _StatusLine(status: status, farbe: farbe);
    }
    final frist = offen.frist;
    return _StatusZeile(
      label: offen.anzahl == 1 ? '1 Tipp offen' : '${offen.anzahl} Tipps offen',
      detail: frist == null ? null : kurzeFrist(frist, DateTime.now()),
      ton: _kTipGold,
      pulsiert: frist != null &&
          frist.difference(DateTime.now()) < const Duration(hours: 1),
    );
  }
}

/// Zustandszeile einer Liga-Karte: übersetzt den Liga-Zustand in Farbe und
/// Text und gibt ihn an [_StatusZeile] weiter.
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
    return _StatusZeile(
      label: status.label,
      detail: status.detail,
      ton: ton,
      // Der laufende Draft ist das einzige, was wirklich tickt.
      pulsiert: status.tone == LeagueStatusTone.laeuft,
    );
  }
}

/// Fußzeile beider Kartensorten: farbiger Punkt, kurzes Wort, leise
/// Zusatzzeile. Texte schrumpfen im Zweifel, statt zu kappen — auf einer
/// Karte, von der vier nebeneinander passen, sagt „Kader ste…" nichts.
class _StatusZeile extends StatelessWidget {
  const _StatusZeile({
    required this.label,
    required this.detail,
    required this.ton,
    required this.pulsiert,
  });

  final String label;
  final String? detail;
  final Color ton;
  final bool pulsiert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (pulsiert)
              PulsingDot(size: 7, color: ton)
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: ton, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            // Den Ton trägt der Punkt, nicht die Schrift: auf der farbigen
            // Karte wäre farbige Schrift schlecht zu lesen.
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label,
                    maxLines: 1,
                    style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 13, top: 1),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(detail!,
                  maxLines: 1,
                  style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 11)),
            ),
          ),
      ],
    );
  }
}

/// Letzte Karte einer Reihe: neu anlegen oder beitreten.
class _NewEntryCard extends ConsumerWidget {
  const _NewEntryCard({required this.label, required this.hoehe});

  final String label;
  final double hoehe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: SizedBox(
        width: leagueCardWidth(context),
        height: hoehe,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showCreateOrJoin(context, ref),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.8)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      size: 22, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 3),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
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
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final league = Leagues.byId(round.leagueId);
    // Mehrere Wettbewerbe → „Bundesliga +2".
    final extra = round.competitions.length - 1;
    final wettbewerb = extra > 0 ? '${league.name} +$extra' : league.name;
    final farbe = parseColor(round.logoColor) ?? _kTipGold;

    final myId = ref.watch(currentUserProvider)?.id;
    final showBadge =
        round.isPublic && round.isInviteOnly && myId == round.createdBy;
    final pending = showBadge
        ? (ref.watch(tipJoinRequestsProvider(round.id)).valueOrNull?.length ?? 0)
        : 0;

    return _PressScale(
      child: SizedBox(
        width: leagueCardWidth(context),
        height: _kTipCardHeight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              activateRound(ref, round);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
            },
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: kartenVerlauf(farbe, scheme, dark),
                border: Border.all(color: farbe.withValues(alpha: 0.65)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 8, 8, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _RoundMark(round: round, farbe: farbe, size: 24),
                              const Spacer(),
                              if (pending > 0) _CountBadge(count: pending),
                            ],
                          ),
                          const Spacer(),
                          Flexible(
                            child: Text(
                              round.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05),
                            ),
                          ),
                          // Der Wettbewerb schrumpft statt zu kappen: aus
                          // „Bundesliga +1" darf nicht „Bundesli…" werden.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              wettbewerb,
                              maxLines: 1,
                              style: TextStyle(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.6),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                  _KartenSockel(
                    farbe: farbe,
                    child: _OffeneTippsZeile(roundId: round.id, farbe: farbe),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Was auf dieser Karte noch zu tun ist: offene Tipps und bis wann. Lädt
/// still nach — solange nichts feststeht, bleibt die Zeile leer, statt einen
/// Ladepunkt in jede Karte zu setzen.
class _OffeneTippsZeile extends ConsumerWidget {
  const _OffeneTippsZeile({required this.roundId, required this.farbe});

  final String roundId;
  final Color farbe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final offen = ref.watch(offeneTippsProvider(roundId)).valueOrNull;
    if (offen == null) return const SizedBox(height: 26);
    if (offen.anzahl == 0) {
      return _StatusZeile(
        label: 'Alles getippt',
        detail: null,
        ton: scheme.onSurfaceVariant,
        pulsiert: false,
      );
    }
    final frist = offen.frist;
    return _StatusZeile(
      label: offen.anzahl == 1 ? '1 Tipp offen' : '${offen.anzahl} Tipps offen',
      detail: frist == null ? null : kurzeFrist(frist, DateTime.now()),
      ton: farbe,
      // Es drängt: das nächste Spiel stößt in unter einer Stunde an.
      pulsiert: frist != null &&
          frist.difference(DateTime.now()) < const Duration(hours: 1),
    );
  }
}

/// Zeichen einer Tipprunde: eigenes Logo, sonst die MatchUp-Marke in Gold.
class _RoundMark extends StatelessWidget {
  const _RoundMark(
      {required this.round, required this.farbe, required this.size});

  final TipRound round;
  final Color farbe;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasCustom = (round.logoUrl != null && round.logoUrl!.isNotEmpty) ||
        (round.logoEmoji != null && round.logoEmoji!.isNotEmpty);
    if (hasCustom) {
      return AppAvatar(
        imageUrl: round.logoUrl,
        emoji: round.logoEmoji,
        colorHex: round.logoColor,
        fallbackIcon: Icons.emoji_events_outlined,
        size: size,
        cornerRadius: 8,
      );
    }
    return Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(color: farbe, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: MatchUpChevron(size: size * 0.5, color: MatchUpColors.base),
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

/// Auswahl beim „+": Fantasy-Liga, Tippspiel oder einer bestehenden Runde
/// beitreten. Gibt `'fantasy'`, `'tip'` bzw. `'join'` zurück.
///
/// Der Schirm hatte zwei bildschirmfüllende Bilder mit je einem Wort darauf —
/// hübsch, aber er beantwortete die eine Frage nicht, die hier ansteht:
/// **was ist der Unterschied?** Jede Karte sagt das jetzt in einer Zeile, und
/// die Höhen stehen fest, statt sich über den ganzen Schirm zu ziehen.
class _CreateOrJoinScreen extends StatelessWidget {
  const _CreateOrJoinScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Neu starten'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Schließen',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(
              'Was möchtest du spielen?',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Beides geht mit denselben Freunden — und beides kannst du '
              'mehrfach haben.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 18),
            _StartKarte(
              farbe: MatchUpColors.green,
              bild: 'assets/images/fantasy_bg.jpg',
              titel: 'Fantasy',
              zeile: 'Spieler draften, Kader managen, Woche für Woche punkten',
              onTap: () => Navigator.of(context).pop('fantasy'),
            ),
            const SizedBox(height: 12),
            _StartKarte(
              farbe: _kTipGold,
              bild: 'assets/images/tippspiel_bg.jpg',
              titel: 'Tippspiel',
              zeile: 'Ergebnisse tippen, Punkte sammeln, Tabelle klettern',
              onTap: () => Navigator.of(context).pop('tip'),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                    child: Divider(
                        color:
                            scheme.outlineVariant.withValues(alpha: 0.7))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('ODER',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      )),
                ),
                Expanded(
                    child: Divider(
                        color:
                            scheme.outlineVariant.withValues(alpha: 0.7))),
              ],
            ),
            const SizedBox(height: 16),
            _BeitretenKarte(onTap: () => Navigator.of(context).pop('join')),
          ],
        ),
      ),
    );
  }
}

/// Eine der beiden Startkarten. Feste Höhe statt `Expanded`: auf einem großen
/// Gerät wuchsen die alten Felder ins Riesenhafte, auf einem kleinen drückten
/// sie den „Beitreten"-Weg aus dem Bild.
class _StartKarte extends StatelessWidget {
  const _StartKarte({
    required this.farbe,
    required this.bild,
    required this.titel,
    required this.zeile,
    required this.onTap,
  });

  final Color farbe;
  final String bild;
  final String titel;
  final String zeile;
  final VoidCallback onTap;

  static const _hoehe = 168.0;
  static final _radius = BorderRadius.circular(20);

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      child: SizedBox(
        height: _hoehe,
        child: Container(
          // Rahmen im Vordergrund → liegt ohne Naht über Bild und Ripple.
          foregroundDecoration: BoxDecoration(
            borderRadius: _radius,
            border: Border.all(color: farbe.withValues(alpha: 0.65), width: 1.5),
          ),
          child: Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            borderRadius: _radius,
            child: Ink.image(
              image: AssetImage(bild),
              fit: BoxFit.cover,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Senkrechter Verlauf: oben nur ein Farbschleier, damit
                    // das Bild sichtbar bleibt, unten fast deckend. Schräg
                    // gelegt lag die Unterzeile teils auf hellem Rasen und
                    // war schlecht zu lesen.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            farbe.withValues(alpha: 0.16),
                            MatchUpColors.base.withValues(alpha: 0.55),
                            MatchUpColors.base.withValues(alpha: 0.96),
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: farbe,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: MatchUpChevron(
                                size: 18, color: MatchUpColors.base),
                          ),
                          const Spacer(),
                          Text(
                            titel,
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  zeile,
                                  maxLines: 2,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.82),
                                    fontSize: 13,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 20, color: farbe),
                            ],
                          ),
                        ],
                      ),
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

/// Der dritte Weg: einer bestehenden Runde beitreten. Bewusst ruhiger als die
/// beiden Startkarten — wer einen Code hat, sucht ihn gezielt.
class _BeitretenKarte extends StatelessWidget {
  const _BeitretenKarte({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.9)),
            ),
            child: Row(
              children: [
                Icon(Icons.vpn_key_outlined,
                    size: 22, color: scheme.onSurfaceVariant),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Einer Runde beitreten',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('Mit dem Einladungscode von Freunden',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

