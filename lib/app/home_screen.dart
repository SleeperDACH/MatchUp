import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';
import 'league_screen.dart';

/// Startbildschirm: meine Ligen (Tipprunden) auswählen, neue erstellen
/// oder beitreten. Die Tippabgabe gibt es erst innerhalb einer Liga.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tippspiel'),
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
        onRefresh: () async => ref.invalidate(myRoundsProvider),
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _SectionHeader(title: 'Meine Ligen'),
            ..._buildLeagueSection(context, ref, user != null),
            const SizedBox(height: 20),
            _SectionHeader(title: 'Ohne Liga'),
            Card(
              child: ListTile(
                leading: Icon(Icons.phone_iphone,
                    color: Theme.of(context).colorScheme.primary),
                title: const Text('Schnelltippen'),
                subtitle: const Text(
                    'Lokal auf diesem Gerät, ohne Konto und Mitspieler'),
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

  List<Widget> _buildLeagueSection(
      BuildContext context, WidgetRef ref, bool loggedIn) {
    if (!AppConfig.isSupabaseConfigured) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Ligen brauchen eine Server-Verbindung. Starte die App über '
              './run_dev.sh (siehe README) — Schnelltippen geht auch so.',
            ),
          ),
        ),
      ];
    }

    if (!loggedIn) {
      return [
        Card(
          child: ListTile(
            leading: Icon(Icons.login,
                color: Theme.of(context).colorScheme.primary),
            title: const Text('Anmelden oder registrieren'),
            subtitle: const Text(
                'Ligen mit Freunden: erstellen, beitreten, gegeneinander tippen'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen())),
          ),
        ),
      ];
    }

    final rounds = ref.watch(myRoundsProvider);
    return [
      rounds.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Ligen konnten nicht geladen werden: $e'),
          ),
        ),
        data: (list) => Column(
          children: [
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Noch keine Liga. Erstelle eine und lade Freunde mit dem '
                  'Einladungscode ein!',
                  textAlign: TextAlign.center,
                ),
              ),
            for (final round in list) _LeagueCard(round: round),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Neue Liga'),
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
}

class _LeagueCard extends ConsumerWidget {
  const _LeagueCard({required this.round});

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
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LeagueScreen(round: round)));
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

// ---------------------------------------------------------------------
// Liga erstellen / beitreten (auch vom LeagueScreen aus nutzbar)
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
        SnackBar(content: Text('Liga konnte nicht erstellt werden: $e')));
  }
}

Future<void> joinRoundFlow(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Liga beitreten'),
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
      title: const Text('Neue Liga erstellen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name der Liga',
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
