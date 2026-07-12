import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transfer_deal.dart';
import '../providers.dart';

/// „Done Deals": strukturierte, finalisierte Bundesliga-Transfers aus
/// Sportmonks — getrennt nach Zugängen und Abgängen.
class DoneDealsScreen extends ConsumerWidget {
  const DoneDealsScreen({super.key});

  static const _green = Color(0xFF4ADE6A);
  static const _red = Color(0xFFF23030);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(doneDealsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Done Deals'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Zugänge'),
            Tab(text: 'Abgänge'),
          ]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _centered(context, 'Transfers konnten nicht '
              'geladen werden.\n$e'),
          data: (deals) {
            final zugaenge = deals.where((d) => d.toBundesliga).toList();
            final abgaenge = deals.where((d) => d.fromBundesliga).toList();
            return TabBarView(
              children: [
                _DealList(deals: zugaenge, incoming: true, empty: 'Aktuell keine Zugänge.'),
                _DealList(deals: abgaenge, incoming: false, empty: 'Aktuell keine Abgänge.'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _centered(BuildContext context, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

class _DealList extends ConsumerWidget {
  const _DealList(
      {required this.deals, required this.incoming, required this.empty});

  final List<TransferDeal> deals;
  final bool incoming;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (deals.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(empty,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(doneDealsProvider),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: deals.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, i) => _DealTile(deal: deals[i], incoming: incoming),
      ),
    );
  }
}

class _DealTile extends StatelessWidget {
  const _DealTile({required this.deal, required this.incoming});

  final TransferDeal deal;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = incoming ? DoneDealsScreen._green : DoneDealsScreen._red;
    // Beim Zugang ist das aufnehmende Team der Bundesligist (hervorheben),
    // beim Abgang der abgebende.
    final club = incoming ? deal.toTeam : deal.fromTeam;
    final other = incoming ? deal.fromTeam : deal.toTeam;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(incoming ? Icons.south_west : Icons.north_east,
              size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.player,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        incoming ? 'von $other' : 'zu $other',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(club,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: accent)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(deal.amountLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              if (deal.date != null) ...[
                const SizedBox(height: 2),
                Text(_date(deal.date!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
}
