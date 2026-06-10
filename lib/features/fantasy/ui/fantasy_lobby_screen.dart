import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';
import 'draft_room_screen.dart';
import 'fantasy_table_screen.dart';
import 'free_agency_screen.dart';
import 'my_team_screen.dart';
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
    // Live-Status, damit der Button nach Draft-Start sofort umschaltet.
    final live = ref.watch(draftLeagueProvider(league.id)).valueOrNull ?? league;
    final isAdmin = myUserId == league.createdBy;

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
            if (live.draftStatus != DraftStatus.setup) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Mein Team'),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => MyTeamScreen(league: live))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.leaderboard_outlined),
                      label: const Text('Tabelle'),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => FantasyTableScreen(league: live))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Free Agency'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FreeAgencyScreen(league: live))),
              ),
            ],
            const SizedBox(height: 16),
            _draftButton(context, ref, live, isAdmin),
          ],
        ),
      ),
    );
  }

  Widget _draftButton(
      BuildContext context, WidgetRef ref, FantasyLeague live, bool isAdmin) {
    void openRoom() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DraftRoomScreen(league: live)));

    Future<void> run(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      try {
        await action();
        ref.invalidate(fantasyManagersProvider(league.id));
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
        if (!isAdmin) {
          return const _DisabledHint(
              icon: Icons.hourglass_empty,
              text: 'Warten auf den Draft-Start durch den Admin');
        }
        return FilledButton.icon(
          icon: const Icon(Icons.sports),
          label: Text(dynasty ? 'Haupt-Draft starten' : 'Draft starten'),
          onPressed: () => run(() => repo.startDraft(league.id)),
        );
      case DraftStatus.drafting:
        return FilledButton.icon(
          icon: const Icon(Icons.sports),
          label: Text(dynasty ? 'Zum ${live.draftPhase.label}' : 'Zum Draft'),
          onPressed: openRoom,
        );
      case DraftStatus.done:
        // Dynasty: nach dem Haupt-Draft folgt der U20-Draft.
        if (dynasty && live.draftPhase == DraftPhase.startup) {
          if (!isAdmin) {
            return const _DisabledHint(
                icon: Icons.hourglass_empty,
                text: 'Haupt-Draft beendet — der Admin startet den U20-Draft');
          }
          return Column(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('U20-Draft starten'),
                onPressed: () => run(() => repo.startU20Draft(league.id)),
              ),
              const SizedBox(height: 6),
              Text(
                'U20-Spieler & Auslands-Neuzugänge sind jetzt wählbar.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          );
        }
        return FilledButton.icon(
          icon: const Icon(Icons.emoji_events),
          label: const Text('Draft-Ergebnis'),
          onPressed: openRoom,
        );
    }
  }
}

class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  style: TextStyle(color: scheme.onSurfaceVariant))),
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
