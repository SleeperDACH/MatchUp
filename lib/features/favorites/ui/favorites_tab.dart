import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/match_detail_screen.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/league_logo.dart';
import '../../../core/models/models.dart';
import '../../../core/models/team_fixture.dart';
import '../../news/models/news_item.dart';
import '../../news/providers.dart';
import '../../news/ui/news_tile.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../favorites.dart';
import 'favorites_manage_screen.dart';

/// Reine Sportmonks-Team-ID aus dem Favoriten-Key (`sportmonks:503` → `503`).
String _teamId(String key) => key.split(':').last;

/// Sortierreihenfolge der Ligen: 1. Bundesliga … 3. Liga, Frauen zuletzt.
int _leagueOrder(String? id) => switch (id) {
      'bundesliga' => 0,
      'bundesliga2' => 1,
      'liga3' => 2,
      'frauen_bundesliga' => 3,
      _ => 4,
    };

/// Basisname eines Teams ohne Frauen-Suffix („Hamburger SV W" → „Hamburger SV").
String _clubBase(String label) {
  final m = RegExp(r'^(.*?)\s+(W|Women|Frauen)$', caseSensitive: false)
      .firstMatch(label.trim());
  return (m != null ? m.group(1)! : label).trim();
}

/// Fasst Favoriten desselben Vereins zu einem gemeinsamen Tab zusammen — etwa
/// Männer- und Frauen-Team (Spielplan und News laufen dann zusammen).
class _FavGroup {
  _FavGroup(this.base);
  final String base;
  final List<Favorite> members = [];

  /// Anzeigename: bei einem einzelnen Team dessen voller Name, sonst der Basis-
  /// Vereinsname (ohne „W").
  String get label => members.length == 1 ? members.first.label : base;
  String? get iconUrl =>
      members.firstWhere((f) => f.iconUrl != null, orElse: () => members.first)
          .iconUrl;
  String? get shortName => members.first.shortName;
  String get key => members.map((f) => f.key).join('+');

  /// Beste (niedrigste) Liga-Reihenfolge über alle Team-Teile — für die
  /// Sortierung der Auswahl (Männer-Team bestimmt die Einordnung).
  int get leagueOrder => members
      .map((f) => _leagueOrder(f.leagueId))
      .fold(9, (a, b) => a < b ? a : b);

  /// Manuelle Sortierposition (kleinste über die Team-Teile); null = keine.
  int? get manualOrder {
    int? m;
    for (final f in members) {
      final s = f.sortOrder;
      if (s != null && (m == null || s < m)) m = s;
    }
    return m;
  }

  List<String> get teamIds => [for (final f in members) _teamId(f.key)];
  List<({String teamId, String name, String? leagueId})> get newsArgs => [
        for (final f in members)
          (teamId: _teamId(f.key), name: f.label, leagueId: f.leagueId)
      ];
}

/// Gruppiert die Favoriten nach Basis-Vereinsnamen (Reihenfolge erhalten).
List<_FavGroup> _groupFavorites(List<Favorite> favs) {
  final groups = <String, _FavGroup>{};
  final order = <String>[];
  for (final f in favs) {
    final base = _clubBase(f.label).toLowerCase();
    final g = groups.putIfAbsent(base, () {
      order.add(base);
      return _FavGroup(_clubBase(f.label));
    });
    g.members.add(f);
  }
  // Manuelle Reihenfolge hat Vorrang; sonst nach Liga (1. → 2. → 3. → Frauen).
  // Innerhalb stabil (ursprüngliche Reihenfolge).
  final list = [for (final b in order) groups[b]!];
  final anyManual = list.any((g) => g.manualOrder != null);
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final int c;
    if (anyManual) {
      final ao = a.$2.manualOrder ?? (1 << 30);
      final bo = b.$2.manualOrder ?? (1 << 30);
      c = ao.compareTo(bo);
    } else {
      c = a.$2.leagueOrder.compareTo(b.$2.leagueOrder);
    }
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Favoriten-Tab: Auswahl der favorisierten Teams oben, darunter je Team der
/// wettbewerbsübergreifende Spielplan und ein teamspezifischer News-Feed.
/// Teams favorisiert man über den Button oben rechts.
class FavoritesTab extends ConsumerStatefulWidget {
  const FavoritesTab({super.key});

  @override
  ConsumerState<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends ConsumerState<FavoritesTab> {
  int _selected = 0;

  void _openManage() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FavoritesManageScreen()));

  void _openReorder() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const FavoritesReorderScreen()));

  @override
  Widget build(BuildContext context) {
    // Nur Teams aus den aktuellen Ligen; veraltete Favoriten (z. B. WM-2026-
    // Nationalmannschaften) werden ausgeblendet.
    final favTeams = ref
        .watch(favoritesProvider)
        .where((f) => f.type == FavoriteType.team && _leagueOrder(f.leagueId) < 4)
        .toList();
    // Männer- und Frauen-Team desselben Vereins teilen sich einen Tab.
    final groups = _groupFavorites(favTeams);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Favoriten'),
        actions: [
          if (groups.length > 1)
            IconButton(
              tooltip: 'Reihenfolge sortieren',
              icon: const Icon(Icons.swap_vert),
              onPressed: _openReorder,
            ),
          IconButton(
            tooltip: 'Teams favorisieren',
            icon: const Icon(Icons.add),
            onPressed: _openManage,
          ),
        ],
      ),
      body: groups.isEmpty
          ? _Empty(onAdd: _openManage)
          : _Body(
              groups: groups,
              selected: _selected.clamp(0, groups.length - 1),
              onSelect: (i) => setState(() => _selected = i),
            ),
    );
  }
}

/// Manuelles Sortieren der Favoriten-Reihenfolge (Chips oben) per Ziehen.
/// Liest die Gruppen direkt aus dem Provider (der die Reihenfolge bereits
/// gemäß sort_order liefert); Ziehen speichert die neue Reihenfolge.
class FavoritesReorderScreen extends ConsumerWidget {
  const FavoritesReorderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final favs = ref
        .watch(favoritesProvider)
        .where((f) => f.type == FavoriteType.team && _leagueOrder(f.leagueId) < 4)
        .toList();
    final groups = _groupFavorites(favs);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Reihenfolge')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Ziehe die Teams in deine Wunschreihenfolge — so erscheinen sie '
              'oben im Favoriten-Tab.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
              itemCount: groups.length,
              // newIndex ist bereits um das entfernte Element korrigiert.
              onReorderItem: (oldIndex, newIndex) {
                final reordered = [...groups];
                final g = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, g);
                final flat = [for (final g in reordered) ...g.members];
                ref.read(favoritesProvider.notifier).setManualOrder(flat);
              },
              itemBuilder: (context, i) {
                final g = groups[i];
                return Card(
                  key: ValueKey(g.key),
                  child: ListTile(
                    leading: TeamBadge(
                      team: TeamRef(
                        id: g.key,
                        name: g.label,
                        shortName: g.shortName ?? g.label,
                        iconUrl: g.iconUrl,
                      ),
                      size: 34,
                    ),
                    title: Text(g.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 14),
            const Text('Noch keine Favoriten',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              'Favorisiere deine Teams — hier siehst du dann ihren Spielplan '
              'und aktuelle News.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Team favorisieren'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<_FavGroup> groups;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final group = groups[selected];
    return Column(
      children: [
        // Team-Auswahl (mehrere Favoriten) als Chips.
        if (groups.length > 1)
          SizedBox(
            height: 78,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final g = groups[i];
                final sel = i == selected;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: Container(
                    width: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sel ? scheme.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          // Wappen unbeschnitten (contain) statt rund geclippt.
                          child: TeamBadge(
                            team: TeamRef(
                              id: g.key,
                              name: g.label,
                              shortName: g.shortName ?? g.label,
                              iconUrl: g.iconUrl,
                            ),
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          g.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.0,
                            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            color: sel ? scheme.onSurface : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Expanded(
          child: DefaultTabController(
            // Key: bei Gruppen-Wechsel neu aufbauen (Tab-Zustand + Provider).
            key: ValueKey(group.key),
            length: 2,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).appBarTheme.backgroundColor,
                  child: const TabBar(
                    tabs: [Tab(text: 'Spielplan'), Tab(text: 'News')],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _FixturesTab(teamIds: group.teamIds),
                      _NewsTab(args: group.newsArgs),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Spielplan (wettbewerbsübergreifend)
// ---------------------------------------------------------------------
class _FixturesTab extends ConsumerWidget {
  const _FixturesTab({required this.teamIds});
  final List<String> teamIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncs = [for (final id in teamIds) ref.watch(teamFixturesProvider(id))];
    final anyLoading = asyncs.any((a) => a.isLoading);
    // Spielpläne aller Team-Teile (z. B. Männer + Frauen) zusammenführen.
    final seen = <String>{};
    final fixtures = <TeamFixture>[
      for (final a in asyncs)
        for (final f in (a.valueOrNull ?? const <TeamFixture>[]))
          if (seen.add(f.id)) f
    ];

    if (fixtures.isEmpty) {
      if (anyLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (asyncs.every((a) => a.hasError)) {
        return _Retry(
          message: 'Spielplan konnte nicht geladen werden.',
          onRetry: () {
            for (final id in teamIds) {
              ref.invalidate(teamFixturesProvider(id));
            }
          },
        );
      }
      return const Center(child: Text('Kein Spielplan verfügbar.'));
    }

    final upcoming = [
      for (final f in fixtures)
        if (f.status != FixtureStatus.finished) f
    ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
    final results = [
      for (final f in fixtures)
        if (f.status == FixtureStatus.finished) f
    ]..sort((a, b) => b.kickoff.compareTo(a.kickoff));
    return RefreshIndicator(
      onRefresh: () async {
        for (final id in teamIds) {
          ref.invalidate(teamFixturesProvider(id));
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (upcoming.isNotEmpty) ...[
            const _SectionLabel('Nächste Spiele'),
            ..._withDateHeaders(upcoming),
          ],
          if (results.isNotEmpty) ...[
            const _SectionLabel('Ergebnisse'),
            ..._withDateHeaders(results),
          ],
        ],
      ),
    );
  }
}

/// Fügt vor jedem neuen Kalendertag eine Datums-Überschrift ein (Datum steht
/// damit außerhalb der Spiel-Box, wie im Live-Tab).
List<Widget> _withDateHeaders(List<TeamFixture> list) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (final f in list) {
    final lt = f.kickoff.toLocal();
    final day = DateTime(lt.year, lt.month, lt.day);
    if (lastDay == null || lastDay != day) {
      out.add(_DateHeader(date: day));
      lastDay = day;
    }
    out.add(_FixtureCard(fixture: f));
  }
  return out;
}

/// Datums-Überschrift zwischen den Spiel-Boxen (z. B. „Samstag, 23.08.").
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat('EEEE, dd.MM.', 'de_DE').format(date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

/// Spieltag- bzw. Pokalrunden-Bezeichnung eines Team-Spiels (null = unbekannt).
String? _matchdayLabel(TeamFixture f) {
  if (f.round <= 0) return null;
  final isCup = f.leagueName.toLowerCase().contains('pokal');
  if (isCup) {
    return switch (f.round) {
      1 => '1. Runde',
      2 => '2. Runde',
      3 => 'Achtelfinale',
      4 => 'Viertelfinale',
      5 => 'Halbfinale',
      6 => 'Finale',
      _ => 'Runde ${f.round}',
    };
  }
  return '${f.round}. Spieltag';
}

class _FixtureCard extends StatelessWidget {
  const _FixtureCard({required this.fixture});
  final TeamFixture fixture;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fixture;
    final live = f.status == FixtureStatus.live;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(fixtureId: f.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Wettbewerbslogo (DFB-Pokal freigestellt) und – auf gleicher Höhe –
            // der Spieltag bzw. die Pokalrunde.
            Row(
              children: [
                LeagueLogo(
                  logoUrl: f.leagueLogo,
                  name: f.leagueName,
                  size: 26,
                  fallback: Text(f.leagueName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (_matchdayLabel(f) != null)
                  Text(_matchdayLabel(f)!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    // Name außen, Logo innen (zur Mitte) → Wappen fluchten.
                    child: Row(children: [
                      Expanded(
                        child: Text(f.home.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      TeamBadge(team: f.home, size: 22),
                    ]),
                  ),
                  // Mitte: Uhrzeit (bzw. Ergebnis) mittig — das Datum steht als
                  // Überschrift außerhalb der Box.
                  SizedBox(
                    width: 62,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (f.hasScore)
                          Text('${f.homeScore}:${f.awayScore}',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: live
                                      ? MatchUpColors.red
                                      : scheme.onSurface))
                        else
                          Text(
                              DateFormat('HH:mm').format(f.kickoff.toLocal()),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                        if (live)
                          const Text('● LIVE',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: MatchUpColors.red)),
                      ],
                    ),
                  ),
                  Expanded(
                    // Logo innen (zur Mitte), Name außen → Wappen fluchten.
                    child: Row(children: [
                      TeamBadge(team: f.away, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(f.away.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 15)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Team-News
// ---------------------------------------------------------------------
class _NewsTab extends ConsumerWidget {
  const _NewsTab({required this.args});
  final List<({String teamId, String name, String? leagueId})> args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncs = [for (final a in args) ref.watch(teamNewsProvider(a))];
    final anyLoading = asyncs.any((a) => a.isLoading);
    // News aller Team-Teile zusammenführen, nach URL entdoppeln, neueste zuerst.
    final seen = <String>{};
    final items = <NewsItem>[
      for (final a in asyncs)
        for (final n in (a.valueOrNull ?? const <NewsItem>[]))
          if (seen.add(n.url)) n
    ]..sort((x, y) {
        final xd = x.publishedAt, yd = y.publishedAt;
        if (xd == null && yd == null) return 0;
        if (xd == null) return 1;
        if (yd == null) return -1;
        return yd.compareTo(xd);
      });

    if (items.isEmpty) {
      if (anyLoading) return const Center(child: CircularProgressIndicator());
      if (asyncs.every((a) => a.hasError)) {
        return _Retry(
          message: 'News konnten nicht geladen werden.',
          onRetry: () {
            for (final a in args) {
              ref.invalidate(teamNewsProvider(a));
            }
          },
        );
      }
      return const Center(child: Text('Aktuell keine News für dieses Team.'));
    }
    return RefreshIndicator(
      onRefresh: () async {
        for (final a in args) {
          ref.invalidate(teamNewsProvider(a));
        }
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => NewsTile(item: items[i]),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Erneut laden')),
        ],
      ),
    );
  }
}
