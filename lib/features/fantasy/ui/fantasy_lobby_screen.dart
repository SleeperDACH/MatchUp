import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'player_pool_screen.dart';

/// Lobby einer Fantasy-Liga: Einstellungen, Manager, Einladungscode und
/// Einstieg in den Draft. Der Draft-Raum selbst folgt als nächster Schritt.
class FantasyLobbyScreen extends ConsumerWidget {
  const FantasyLobbyScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final managers = ref.watch(fantasyManagersProvider(league.id));
    final pool = ref.watch(playerPoolProvider);
    final myUserId = ref.watch(currentUserProvider)?.id;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(league.name),
            Text(
              '${league.mode.label} · Saison ${league.season}/${(league.season + 1) % 100}',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.primary),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(fantasyManagersProvider(league.id));
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _SettingsCard(league: league),
            const SizedBox(height: 4),
            if (league.draftStatus == DraftStatus.setup)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(league.inviteCode,
                      style: const TextStyle(
                          fontFamily: 'monospace', letterSpacing: 1.5)),
                  subtitle: const Text('Einladungscode — antippen zum Kopieren'),
                  trailing: const Icon(Icons.copy, size: 18),
                  onTap: () async {
                    await Clipboard.setData(
                        ClipboardData(text: league.inviteCode));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Einladungscode kopiert')));
                    }
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
              child:
                  Text('Manager', style: Theme.of(context).textTheme.titleMedium),
            ),
            managers.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Manager konnten nicht geladen werden: $e'),
              ),
              data: (list) => Column(
                children: [
                  for (final (i, m) in list.indexed)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: scheme.primary.withValues(alpha: 0.15),
                          child: Text('${i + 1}',
                              style: TextStyle(color: scheme.primary)),
                        ),
                        title: Text(
                          m.username,
                          style: m.userId == myUserId
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                        trailing: m.userId == league.createdBy
                            ? const _OwnerChip()
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.groups_2, color: scheme.primary),
                title: const Text('Spielerpool'),
                subtitle: Text(pool.maybeWhen(
                  data: (p) => '${p.length} Spieler verfügbar',
                  orElse: () => 'wird geladen …',
                )),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PlayerPoolScreen())),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.sports),
              label: Text(league.draftStatus == DraftStatus.setup
                  ? 'Draft starten'
                  : 'Zum Draft'),
              onPressed: () => _draftComingSoon(context),
            ),
          ],
        ),
      ),
    );
  }

  void _draftComingSoon(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Draft-Raum kommt als Nächstes'),
        content: Text(
          'Der Snake-Draft mit Pick-Timer (${league.pickTime.label}) ist der '
          'nächste Bauabschnitt. Liga, Manager-Beitritt und der Spielerpool '
          'stehen bereits — du kannst den Pool schon ansehen.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _row(context, Icons.auto_awesome, 'Modus',
                '${league.mode.label} — ${league.mode.tagline}'),
            const Divider(height: 18),
            _row(context, Icons.timer, 'Pickzeit',
                '${league.pickTime.label} (${league.pickTime.isLive ? 'Live-Draft' : 'Slow-Draft'})'),
            const Divider(height: 18),
            _row(context, Icons.people, 'Kader',
                '${league.roster.squadSize} Spieler · ${league.roster.starters} in der Startelf'),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text(label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant)),
        ),
        Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}

class _OwnerChip extends StatelessWidget {
  const _OwnerChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Admin',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: scheme.primary)),
    );
  }
}
