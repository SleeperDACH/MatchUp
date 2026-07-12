import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'news_tile.dart';

/// Vollständige, scrollbare News-Liste eines Themas (Transfers bzw. Ausfälle),
/// neueste zuerst. Über den Home-Screen erreichbar.
class NewsListScreen extends ConsumerWidget {
  const NewsListScreen({
    super.key,
    required this.topic,
    required this.title,
    required this.intro,
  });

  final String topic;
  final String title;
  final String intro;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final newsAsync = ref.watch(newsProvider(topic));

    Widget centered(String text) => ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(newsProvider(topic)),
        child: newsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              centered('News konnten nicht geladen werden.\n$e'),
          data: (items) {
            if (items.isEmpty) {
              return centered(
                  'Gerade keine Meldungen gefunden.\nZieh zum Aktualisieren nach unten.');
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
                    child: Text(intro,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
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
