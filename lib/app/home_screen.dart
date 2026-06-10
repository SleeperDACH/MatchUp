import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/fantasy/ui/create_fantasy_league.dart';
import '../features/fantasy/ui/fantasy_lobby_screen.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import 'league_screen.dart';

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
        title: const Text('Fantasy'),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Abmelden',
              icon: const Icon(Icons.logout),
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
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
                'App über ./run_dev.sh (siehe README) — Schnelltippen geht '
                'auch ohne.',
              )
            else if (user == null)
              const _LoginCard()
            else ...[
              ..._fantasySection(context, ref),
              const SizedBox(height: 24),
              ..._tippspielSection(context, ref),
            ],
            const SizedBox(height: 24),
            _sectionHeader(context, 'Ohne Konto'),
            Card(
              child: ListTile(
                leading: Icon(Icons.phone_iphone,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Schnelltippen'),
                subtitle: const Text(
                    'Tippspiel lokal auf diesem Gerät, ohne Konto'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ref.read(activeRoundProvider.notifier).state = null;
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LeagueScreen(round: null)));
                },
              ),
            ),
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
      Row(
        children: [
          Icon(Icons.sports_soccer,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text('Fantasy',
              style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
        child: Text(
          'Drafte echte Spieler und sammle Punkte nach ihrer Leistung.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: _ModeHero(
              icon: Icons.calendar_today,
              title: 'Fantasy Liga',
              subtitle: 'Eine Saison · Draft',
              onTap: () => createFantasyLeagueFlow(context, FantasyMode.liga),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModeHero(
              icon: Icons.auto_awesome,
              title: 'Dynasty',
              subtitle: 'Kader über Jahre · U20-Draft',
              onTap: () =>
                  createFantasyLeagueFlow(context, FantasyMode.dynasty),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.key, size: 18),
          label: const Text('Mit Code beitreten'),
          onPressed: () => joinFantasyLeagueFlow(context, ref),
        ),
      ),
      leagues.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) =>
            _InfoCard('Fantasy-Ligen konnten nicht geladen werden: $e'),
        data: (list) => Column(
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Noch keine Fantasy-Liga — erstelle oben eine Liga oder '
                  'Dynasty.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
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
      _sectionHeader(context, 'Tippspiel'),
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _InfoCard('Tipprunden konnten nicht geladen werden: $e'),
        data: (list) => Column(
          children: [
            for (final round in list) _TipRoundCard(round: round),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Tipprunde'),
              onPressed: () => createRoundFlow(context, ref),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.key),
              label: const Text('Beitreten'),
              onPressed: () => joinRoundFlow(context, ref),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _sectionHeader(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ModeHero extends StatelessWidget {
  const _ModeHero({
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
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.primary.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
          child: Column(
            children: [
              Icon(icon, size: 34, color: scheme.primary),
              const SizedBox(height: 10),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
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
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(
            league.mode == FantasyMode.dynasty
                ? Icons.auto_awesome
                : Icons.calendar_today,
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Text(league.name),
        subtitle: Text(
            '${league.mode.label} · ${league.draftStatus == DraftStatus.setup ? 'Setup' : league.draftStatus == DraftStatus.drafting ? 'Draft läuft' : 'Saison läuft'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FantasyLobbyScreen(league: league))),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Icon(Icons.emoji_events, color: scheme.primary, size: 20),
        ),
        title: Text(round.name),
        subtitle: Text(league.fixedSeason != null
            ? league.name
            : '${league.name} · Saison ${round.season}/${(round.season + 1) % 100}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          activateRound(ref, round);
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
        },
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primary.withValues(alpha: 0.12),
      child: ListTile(
        leading: Icon(Icons.login, color: scheme.primary),
        title: const Text('Anmelden oder registrieren'),
        subtitle: const Text(
            'Fantasy-Ligen und Tipprunden mit Freunden spielen'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
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

Future<void> joinRoundFlow(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Tipprunde beitreten'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Einladungscode',
          contentPadding: EdgeInsets.symmetric(horizontal: 12),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
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
  try {
    final round = await ref.read(tipRoundRepositoryProvider).joinRound(code);
    ref.invalidate(myRoundsProvider);
    activateRound(ref, round);
    if (!context.mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => LeagueScreen(round: round)));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().contains('Ungültiger Einladungscode')
            ? 'Ungültiger Einladungscode.'
            : 'Beitritt fehlgeschlagen: $e')));
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
