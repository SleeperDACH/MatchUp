import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers.dart';
import '../models/fantasy_models.dart';
import '../providers.dart';

/// Eigener Einstellungen-Bereich einer Fantasy-Liga. Aktuell: Liga löschen
/// (nur der Ersteller). Hier kommen später weitere Liga-Einstellungen dazu.
class FantasyLeagueSettingsScreen extends ConsumerWidget {
  const FantasyLeagueSettingsScreen({super.key, required this.league});

  final FantasyLeague league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isOwner = ref.watch(currentUserProvider)?.id == league.createdBy;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            const Text('Einstellungen'),
            Text(league.name,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.primary)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('Gefahrenzone',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant)),
          ),
          if (isOwner)
            Card(
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Liga löschen',
                    style: TextStyle(
                        color: scheme.error, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    'Entfernt die Liga endgültig — mit Draft, Kadern und allen '
                    'Daten, für alle Mitglieder.'),
                onTap: () => _confirmDelete(context, ref),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Nur der Ersteller der Liga kann sie löschen.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final scheme = Theme.of(context).colorScheme;
    // Vor dem await sichern (überlebt das Wegpoppen, kein Context über Gaps).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liga löschen?'),
        content: Text(
            '„${league.name}" wird mit allen Drafts, Kadern und Daten '
            'endgültig gelöscht. Das kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(fantasyLeagueRepositoryProvider).deleteLeague(league.id);
      ref.invalidate(myFantasyLeaguesProvider);
      navigator.popUntil((r) => r.isFirst); // zurück zum Home
      messenger.showSnackBar(
          const SnackBar(content: Text('Liga gelöscht.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
    }
  }
}
