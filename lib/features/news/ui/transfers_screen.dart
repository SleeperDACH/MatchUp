import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/transfer_deal.dart';
import '../providers.dart';

/// „Transfers": strukturierte, finalisierte Bundesliga-Transfers aus Sportmonks
/// — getrennt nach Zugängen/Abgängen, mit Vereinswappen und Filter nach Verein.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  /// Gewählter Filter-Verein (null = alle).
  String? _club;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(doneDealsProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Transfers'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Zugänge'),
            Tab(text: 'Abgänge'),
          ]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _centered('Transfers konnten nicht geladen '
              'werden.\n$e'),
          data: (deals) {
            // Filter-Vereine (Bundesliga-Seite jedes Deals) inkl. Wappen.
            final clubs = <String, String?>{};
            for (final d in deals) {
              if (d.toBundesliga) clubs[d.toTeam] = d.toLogo;
              if (d.fromBundesliga) clubs[d.fromTeam] = d.fromLogo;
            }
            final clubList = clubs.keys.toList()..sort();

            final zugaenge = deals
                .where((d) =>
                    d.toBundesliga && (_club == null || d.toTeam == _club))
                .toList();
            final abgaenge = deals
                .where((d) =>
                    d.fromBundesliga && (_club == null || d.fromTeam == _club))
                .toList();

            return Column(
              children: [
                _ClubFilterBar(
                  clubs: clubList,
                  logos: clubs,
                  selected: _club,
                  onSelect: (c) => setState(() => _club = c),
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    children: [
                      _DealList(
                          deals: zugaenge,
                          incoming: true,
                          empty: 'Keine Zugänge für diese Auswahl.'),
                      _DealList(
                          deals: abgaenge,
                          incoming: false,
                          empty: 'Keine Abgänge für diese Auswahl.'),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _centered(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}

/// Vereinswappen (Sportmonks-Logo) mit Fallback-Icon.
class ClubCrest extends StatelessWidget {
  const ClubCrest({super.key, required this.url, this.size = 34});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(Icons.shield_outlined,
        size: size * 0.8, color: Theme.of(context).colorScheme.onSurfaceVariant);
    if (url == null || url!.isEmpty) return SizedBox(width: size, height: size, child: Center(child: fallback));
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(url!,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Center(child: fallback)),
    );
  }
}

/// Horizontale Filter-Leiste: „Alle" + je Verein ein Chip mit Wappen.
class _ClubFilterBar extends StatelessWidget {
  const _ClubFilterBar({
    required this.clubs,
    required this.logos,
    required this.selected,
    required this.onSelect,
  });

  final List<String> clubs;
  final Map<String, String?> logos;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          ChoiceChip(
            label: const Text('Alle'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          const SizedBox(width: 8),
          for (final c in clubs) ...[
            ChoiceChip(
              avatar: ClubCrest(url: logos[c], size: 22),
              label: Text(c),
              selected: selected == c,
              onSelected: (_) => onSelect(selected == c ? null : c),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
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
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, i) =>
            _DealTile(deal: deals[i], incoming: incoming),
      ),
    );
  }
}

class _DealTile extends StatelessWidget {
  const _DealTile({required this.deal, required this.incoming});

  final TransferDeal deal;
  final bool incoming;

  static const _green = Color(0xFF4ADE6A);
  static const _red = Color(0xFFF23030);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = incoming ? _green : _red;
    // Beim Zugang ist das aufnehmende Team der Bundesligist (Wappen links),
    // beim Abgang das abgebende.
    final clubLogo = incoming ? deal.toLogo : deal.fromLogo;
    final otherName = incoming ? deal.fromTeam : deal.toTeam;
    final otherLogo = incoming ? deal.fromLogo : deal.toLogo;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          ClubCrest(url: clubLogo, size: 38),
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
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(incoming ? Icons.south_west : Icons.north_east,
                        size: 13, color: accent),
                    const SizedBox(width: 4),
                    ClubCrest(url: otherLogo, size: 16),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(otherName,
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
