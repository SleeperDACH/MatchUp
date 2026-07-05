import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_league_screen.dart';
import '../features/messaging/providers.dart';
import '../features/messaging/ui/conversations_screen.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
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
        // Tippspiel / Redraft / Dynasty zur Auswahl.
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
              ..._fantasySection(context, ref),
              const SizedBox(height: 24),
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
                  for (final league in list) _FantasyLeagueCard(league: league),
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
                  for (final round in list) _TipRoundCard(round: round),
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
    final scheme = Theme.of(context).colorScheme;
    final (statusLabel, statusColor) = switch (league.draftStatus) {
      DraftStatus.setup => ('Setup', scheme.onSurfaceVariant),
      DraftStatus.drafting => ('Draft läuft', scheme.primary),
      DraftStatus.done => ('Saison läuft', scheme.primary),
    };
    return _LeagueTile(
      icon: league.mode == FantasyMode.dynasty
          ? Icons.auto_awesome
          : Icons.calendar_today,
      title: league.name,
      subtitle:
          '${league.mode.label} · Saison ${league.season}/${(league.season + 1) % 100}',
      chipLabel: statusLabel,
      chipColor: statusColor,
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
      subtitle: league.fixedSeason != null
          ? 'Tippspiel'
          : 'Saison ${round.season}/${(round.season + 1) % 100}',
      chipLabel: league.name,
      chipColor: Theme.of(context).colorScheme.primary,
      onTap: () {
        activateRound(ref, round);
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
      },
    );
  }
}

/// Einheitliche, ruhig getönte Liga-Karte für den Homescreen (Fantasy &
/// Tippspiel): Icon-Kachel, Name, Status-Chip und Kontextzeile.
class _LeagueTile extends StatelessWidget {
  const _LeagueTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.chipLabel,
    required this.chipColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String chipLabel;
  final Color chipColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _StatusChip(label: chipLabel, color: chipColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
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
// Tippspiel: Tipprunde erstellen / beitreten
// ---------------------------------------------------------------------

Future<void> createRoundFlow(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<(String, LeagueInfo)>(
    context: context,
    builder: (_) => const _CreateRoundDialog(),
  );
  if (result == null) return;
  final (name, league) = result;
  try {
    final round = await ref.read(tipRoundRepositoryProvider).createRound(
          name: name,
          league: league,
          season: league.seasonFor(DateTime.now()),
        );
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipprunde konnte nicht erstellt werden: $e')));
  }
}

/// Gemeinsamer Beitreten-Flow für alle Spielmodi: Ein Einladungscode kann zu
/// einer Fantasy-Liga oder einer Tipprunde gehören. Wir probieren zuerst
/// Fantasy, fällt der Code dort als unbekannt durch, dann das Tippspiel.
/// Auswahl-Sheet für den Erstellen-Knopf: Tippspiel, Redraft oder Dynasty.
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
              child: Text('Neu erstellen',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
          ),
          _CreateOption(
            icon: Icons.emoji_events_outlined,
            title: 'Tippspiel',
            subtitle: 'Ergebnisse tippen, Punkte sammeln',
            onTap: () {
              Navigator.of(ctx).pop();
              createRoundFlow(context, ref);
            },
          ),
          _CreateOption(
            icon: Icons.calendar_today,
            title: 'Redraft',
            subtitle: 'Fantasy: eine Saison, danach neuer Draft',
            onTap: () {
              Navigator.of(ctx).pop();
              createFantasyQuickFlow(context, ref, FantasyMode.liga);
            },
          ),
          _CreateOption(
            icon: Icons.auto_awesome,
            title: 'Dynasty',
            subtitle: 'Fantasy: Kader über Jahre, U20-Draft',
            onTap: () {
              Navigator.of(ctx).pop();
              createFantasyQuickFlow(context, ref, FantasyMode.dynasty);
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

class _CreateRoundDialog extends StatefulWidget {
  const _CreateRoundDialog();

  @override
  State<_CreateRoundDialog> createState() => _CreateRoundDialogState();
}

class _CreateRoundDialogState extends State<_CreateRoundDialog> {
  final _name = TextEditingController();
  LeagueInfo _league = Leagues.all.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (_name.text.trim().length < 3) return;
    Navigator.of(context).pop((_name.text.trim(), _league));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neue Tipprunde'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name der Tipprunde',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<LeagueInfo>(
            initialValue: _league,
            decoration: const InputDecoration(
              labelText: 'Wettbewerb',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            items: [
              for (final league in Leagues.all)
                DropdownMenuItem(value: league, child: Text(league.name)),
            ],
            onChanged: (league) => setState(() => _league = league ?? _league),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Erstellen')),
      ],
    );
  }
}
