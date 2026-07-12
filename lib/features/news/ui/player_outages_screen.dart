import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'news_tile.dart';

/// „Verletzungen & Sperren": aktuelle Ausfall-Schlagzeilen der Bundesliga
/// (RSS-Live-News). Über den Home-Screen erreichbar.
class PlayerOutagesScreen extends ConsumerWidget {
  const PlayerOutagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final newsAsync = ref.watch(newsProvider('injuries'));

    return Scaffold(
      appBar: AppBar(title: const Text('Verletzungen & Sperren')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(newsProvider('injuries')),
        child: newsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('News konnten nicht geladen werden.\n$e',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                          'Gerade keine Ausfall-Meldungen gefunden.\n'
                          'Zieh zum Aktualisieren nach unten.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: items.length + 1,
              separatorBuilder: (_, i) =>
                  i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Aktuelle Schlagzeilen zu Verletzungen und Sperren in der '
                      'Bundesliga. Tippen öffnet den Artikel.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return NewsTile(item: items[i - 1]);
              },
            );
          },
        ),
      ),
    );
  }
}
