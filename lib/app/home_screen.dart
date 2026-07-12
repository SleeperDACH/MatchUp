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
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/create_tip_round.dart';
import '../features/tippspiel/ui/tip_rank_chip.dart';
import 'league_screen.dart';
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
      appBar: AppBar(
        centerTitle: true,
        // Erstellen-Knopf oben links (mit Label, damit klar ist wofür):
        // zuerst Fantasy oder Tippspiel wählen.
        leadingWidth: 116,
        leading: (configured && user != null)
            ? TextButton.icon(
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Erstellen'),
                onPressed: () => showCreateChooser(context, ref),
              )
            : null,
        title: const _MatchUpTitle(),
        actions: [
          // Gemeinsamer Beitreten-Knopf für alle Spielmodi (Fantasy + Tippspiel).
          if (configured && user != null)
            TextButton.icon(
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Beitreten'),
              onPressed: () => joinAnyFlow(context, ref),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myFantasyLeaguesProvider);
          ref.invalidate(myRoundsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (!configured)
              const _InfoCard(
                'Fantasy & Ligen brauchen eine Server-Verbindung. Starte die '
                'App über ./run_dev.sh (siehe README).',
              )
            else ...[
              const _WelcomeHeader(),
              const SizedBox(height: 16),
              const _LiveMatchesStrip(),
              ..._fantasySection(context, ref),
              const SizedBox(height: 18),
              ..._tippspielSection(context, ref),
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
      _sectionHeader(context, 'Fantasy', Icons.shield_outlined),
      leagues.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _InfoCard('Fantasy-Ligen konnten nicht geladen werden: $e'),
        data: (list) => list.isEmpty
            ? const _EmptyHint(
                'Noch keine Fantasy-Liga — oben links mit + eine Redraft- '
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
      _sectionHeader(context, 'Tippspiel', Icons.emoji_events_outlined),
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _InfoCard('Tipprunden konnten nicht geladen werden: $e'),
        data: (list) => list.isEmpty
            ? const _EmptyHint(
                'Noch keine Tipprunde — oben links mit + ein Tippspiel '
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

  Widget _sectionHeader(BuildContext context, String title, IconData icon) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

/// Horizontaler „Live & heute"-Streifen: Spiele der Wettbewerbe, in denen der
/// Nutzer aktiv ist (Tipprunden-Ligen + Bundesliga bei Fantasy). Zeigt laufende
/// Partien zuerst; blendet sich aus, wenn heute nichts läuft.
class _LiveMatchesStrip extends ConsumerWidget {
  const _LiveMatchesStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rounds = ref.watch(myRoundsProvider).valueOrNull ?? const [];
    final fantasy = ref.watch(myFantasyLeaguesProvider).valueOrNull ?? const [];
    final leagueIds = <String>{
      for (final r in rounds) r.leagueId,
      if (fantasy.isNotEmpty) 'bundesliga',
    };
    if (leagueIds.isEmpty) return const SizedBox.shrink();

    final today = DateUtils.dateOnly(DateTime.now());
    final seen = <String>{};
    final items = <Fixture>[];
    for (final id in leagueIds) {
      final fx = ref.watch(leagueSeasonFixturesProvider(id)).valueOrNull;
      if (fx == null) continue;
      for (final f in fx) {
        final isLive = f.status == FixtureStatus.live;
        final isToday = DateUtils.dateOnly(f.kickoff.toLocal()) == today;
        if ((isLive || isToday) && seen.add(f.id)) items.add(f);
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();

    items.sort((a, b) {
      final la = a.status == FixtureStatus.live ? 0 : 1;
      final lb = b.status == FixtureStatus.live ? 0 : 1;
      return la != lb ? la - lb : a.kickoff.compareTo(b.kickoff);
    });
    final anyLive = items.any((f) => f.status == FixtureStatus.live);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(anyLive ? Icons.circle : Icons.sports_soccer,
                  size: anyLive ? 10 : 16,
                  color: anyLive
                      ? MatchUpColors.red
                      : Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(anyLive ? 'Live' : 'Heute',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => _LiveMatchCard(fixture: items[i]),
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// Kompakte Ergebnis-/Anstoß-Kachel im Live-Streifen.
class _LiveMatchCard extends StatelessWidget {
  const _LiveMatchCard({required this.fixture});

  final Fixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = fixture.status == FixtureStatus.live;
    final finished = fixture.status == FixtureStatus.finished;
    final k = fixture.kickoff.toLocal();
    final timeText =
        '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
    final hasScore = fixture.hasScore;

    Widget teamRow(String name, int? score) => Row(
          children: [
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Text(hasScore ? '${score ?? 0}' : '',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: live ? MatchUpColors.red : scheme.onSurface)),
          ],
        );

    return Container(
      width: 156,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: live
                ? MatchUpColors.red.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (live) ...[
                Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                        color: MatchUpColors.red, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('LIVE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: MatchUpColors.red)),
              ] else
                Text(finished ? 'Endstand' : timeText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          teamRow(fixture.home.shortName, fixture.homeScore),
          const SizedBox(height: 2),
          teamRow(fixture.away.shortName, fixture.awayScore),
        ],
      ),
    );
  }
}

/// Persönliche Begrüßung oben auf dem Home-Tab.
class _WelcomeHeader extends ConsumerWidget {
  const _WelcomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUsernameProvider).valueOrNull;
    final unread = ref.watch(hasUnreadDmsProvider);
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
                Text(
                  name == null ? 'Willkommen 👋' : 'Hallo, $name 👋',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Deine Ligen & Tipprunden auf einen Blick.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.72)),
                ),
              ],
            ),
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
              if (unread)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: MatchUpColors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: MatchUpColors.base, width: 2),
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

class _FantasyLeagueCard extends StatelessWidget {
  const _FantasyLeagueCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return _LeagueTile(
      icon: league.mode == FantasyMode.dynasty
          ? Icons.auto_awesome
          : Icons.calendar_today,
      title: league.name,
      subtitle: league.mode.label,
      logoUrl: league.logoUrl,
      logoEmoji: league.logoEmoji,
      logoColor: league.logoColor,
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
    return _LeagueTile(
      icon: icon,
      title: round.name,
      subtitle: league.name,
      logoUrl: round.logoUrl,
      logoEmoji: round.logoEmoji,
      logoColor: round.logoColor,
      trailing: TipRankChip(round: round),
      onTap: () {
        activateRound(ref, round);
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
      },
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Bewusst keine Card/Box: schlichte, randlose Listenzeile.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              AppAvatar(
                imageUrl: logoUrl,
                emoji: logoEmoji,
                colorHex: logoColor,
                fallbackIcon: icon,
                size: 40,
                cornerRadius: 10,
              ),
              const SizedBox(width: 12),
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
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
              const SizedBox(width: 12),
              // Nach rechts gedrehter MatchUp-Doppelchevron in Weiß.
              const RotatedBox(
                quarterTurns: 1,
                child: MatchUpChevron(size: 16, color: Colors.white),
              ),
            ],
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
      indent: 56,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
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

/// Auswahl-Sheet für den Erstellen-Knopf: erst die Kategorie **Fantasy** oder
/// **Tippspiel** wählen — danach führt jeweils ein eigener Screen durch Name
/// und Modus (Fantasy: Redraft/Dynasty; Tippspiel: kombinierbare Modi).
void showCreateChooser(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Was möchtest du erstellen?',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          _CreateOption(
            icon: Icons.shield_outlined,
            title: 'Fantasy',
            subtitle: 'Kader draften und Spieltage gewinnen (Redraft / Dynasty)',
            onTap: () {
              Navigator.of(ctx).pop();
              createFantasyLeagueFlow(context, FantasyMode.liga);
            },
          ),
          _CreateOption(
            icon: Icons.emoji_events_outlined,
            title: 'Tippspiel',
            subtitle: 'Ergebnisse tippen, Punkte sammeln (kombinierbare Modi)',
            onTap: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CreateTipRoundScreen()));
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _CreateOption extends StatelessWidget {
  const _CreateOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        child: Icon(icon, color: scheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      onTap: onTap,
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
