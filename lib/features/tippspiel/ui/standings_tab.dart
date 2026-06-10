import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/tip_round.dart';
import '../providers.dart';

/// Rangliste einer Liga inkl. Einladungscode zum Teilen.
class StandingsTab extends ConsumerWidget {
  const StandingsTab({super.key, required this.round});

  final TipRound round;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider(round.id));
    final myUserId = ref.watch(currentUserProvider)?.id;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(standingsProvider(round.id)),
      child: ListView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.key),
              title: Text(round.inviteCode,
                  style: const TextStyle(
                      fontFamily: 'monospace', letterSpacing: 1.5)),
              subtitle: const Text('Einladungscode — antippen zum Kopieren'),
              trailing: const Icon(Icons.copy, size: 18),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: round.inviteCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Einladungscode kopiert')));
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text('Rangliste',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          standings.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Rangliste konnte nicht geladen werden: $e'),
            ),
            data: (entries) => entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Noch keine gewerteten Tipps in dieser Liga.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    children: [
                      for (final (index, entry) in entries.indexed)
                        Card(
                          child: ListTile(
                            leading: _RankBadge(rank: index + 1),
                            title: Text(
                              entry.username,
                              style: entry.userId == myUserId
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            ),
                            subtitle:
                                Text('${entry.scoredTips} gewertete Tipps'),
                            trailing: Text(
                              '${entry.points} Pkt.',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: rank == 1
          ? scheme.primary.withValues(alpha: 0.25)
          : scheme.surfaceContainerHighest,
      child: Text('$rank',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: rank == 1 ? scheme.primary : scheme.onSurfaceVariant)),
    );
  }
}
