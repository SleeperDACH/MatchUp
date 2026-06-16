import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/models/models.dart';
import '../features/favorites/favorites.dart';
import '../features/tippspiel/providers.dart';
import '../features/tippspiel/ui/team_badge.dart';
import 'league_overview_screen.dart';
import 'theme.dart';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Ein Spiel im Live-Feed, samt zugehöriger Liga.
class _LiveItem {
  const _LiveItem(this.league, this.fixture);
  final LeagueInfo league;
  final Fixture fixture;
}

/// Aktiver Filter der Favoriten-Leiste: ein Team oder eine Liga (oder nichts).
class _Filter {
  const _Filter(this.type, this.key);
  final FavoriteType type;
  final String key;
}

/// Live-Tab im Stil von Toralarm: oben eine Tagesleiste (letzte/nächste 7
/// Tage) zur Tagesauswahl, darunter eine Leiste mit favorisierten Ligen und
/// Teams (Antippen filtert). Gezeigt werden die Spiele des gewählten Tages.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  _Filter? _filter;
  late DateTime _selectedDay;
  ScrollController? _dayController;
  Timer? _refreshTimer;

  static const _dayItemExtent = 60.0; // Breite + Rand je Tageszelle

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    // Eigener Takt (unabhängig von Rebuilds): lädt die Spieldaten neu,
    // solange ein Spiel live ist bzw. zeitnah ansteht/gerade lief — sonst
    // nur ein günstiger Check auf zwischengespeicherten Daten, kein Abruf.
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => _maybeRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dayController?.dispose();
    super.dispose();
  }

  void _maybeRefresh() {
    if (!mounted) return;
    final now = DateTime.now();
    var hasNear = false;
    for (final l in Leagues.all) {
      final fx = ref.read(leagueSeasonFixturesProvider(l.id)).valueOrNull;
      if (fx == null) continue;
      if (fx.any((f) =>
          f.status != FixtureStatus.finished &&
          f.kickoff.difference(now).abs() < const Duration(hours: 3))) {
        hasNear = true;
        break;
      }
    }
    if (!hasNear) return;
    for (final l in Leagues.all) {
      ref.invalidate(leagueSeasonFixturesProvider(l.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final favLeagues =
        favorites.where((f) => f.type == FavoriteType.league).toList();
    final favTeams =
        favorites.where((f) => f.type == FavoriteType.team).toList();

    // Welche Ligen zeigen wir? Die favorisierten — sonst alle verfügbaren.
    final leagueIds = favLeagues.isNotEmpty
        ? favLeagues.map((f) => f.key).toList()
        : [for (final l in Leagues.all) l.id];

    // Fixtures der relevanten Ligen einsammeln (best effort).
    final items = <_LiveItem>[];
    var anyLoading = false;
    Object? error;
    for (final id in leagueIds) {
      final async = ref.watch(leagueSeasonFixturesProvider(id));
      if (async.isLoading) {
        anyLoading = true;
      } else if (async.hasError) {
        error ??= async.error;
      } else {
        final league = Leagues.byId(id);
        for (final f in async.valueOrNull ?? const <Fixture>[]) {
          items.add(_LiveItem(league, f));
        }
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = -7; i <= 7; i++) today.add(Duration(days: i))];
    // Heute (Index 7) beim ersten Aufbau etwa mittig einblenden.
    _dayController ??= ScrollController(
        initialScrollOffset: (7 * _dayItemExtent - 120).clamp(0, 1e9));

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Live')),
      body: Column(
        children: [
          _DateStrip(
            days: days,
            today: today,
            selected: _selectedDay,
            controller: _dayController,
            onSelect: (d) => setState(() => _selectedDay = d),
          ),
          _FavoritesBar(
            leagueIds: leagueIds,
            favTeams: favTeams,
            filter: _filter,
            onSelect: (f) => setState(() => _filter = f),
            onLeagueTap: (id) => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LeagueOverviewScreen(league: Leagues.byId(id)))),
          ),
          Expanded(child: _buildDay(context, items, anyLoading, error)),
        ],
      ),
    );
  }

  Widget _buildDay(BuildContext context, List<_LiveItem> items, bool anyLoading,
      Object? error) {
    if (items.isEmpty && anyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty && error != null) {
      return _Retry(
        message: 'Spiele konnten nicht geladen werden.',
        onRetry: _refresh,
      );
    }

    // Favoriten-Filter anwenden …
    final filter = _filter;
    var list = filter == null
        ? items
        : [
            for (final it in items)
              if (filter.type == FavoriteType.league
                  ? it.league.id == filter.key
                  : (it.fixture.home.id == filter.key ||
                      it.fixture.away.id == filter.key))
                it
          ];
    // … und den gewählten Tag.
    list = [
      for (final it in list)
        if (_sameDay(it.fixture.kickoff.toLocal(), _selectedDay)) it
    ]..sort((a, b) => a.fixture.kickoff.compareTo(b.fixture.kickoff));

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: list.isEmpty
          ? const _Empty('Keine Spiele an diesem Tag.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [for (final it in list) _MatchTile(item: it)],
            ),
    );
  }

  void _refresh() {
    for (final l in Leagues.all) {
      ref.invalidate(leagueSeasonFixturesProvider(l.id));
    }
  }
}

/// Tagesleiste: letzte 7 und nächste 7 Tage; tippen wählt den Tag.
class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.days,
    required this.today,
    required this.selected,
    required this.onSelect,
    this.controller,
  });

  final List<DateTime> days;
  final DateTime today;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 62,
        child: ListView.builder(
          controller: controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: days.length,
          itemBuilder: (context, i) {
            final d = days[i];
            final sel = _sameDay(d, selected);
            final isToday = _sameDay(d, today);
            return GestureDetector(
              onTap: () => onSelect(d),
              child: Container(
                width: 52,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isToday && !sel
                      ? Border.all(color: scheme.primary)
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE', 'de_DE').format(d),
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            sel ? scheme.onPrimary : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: sel
                            ? scheme.onPrimary
                            : (isToday ? scheme.primary : scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Obere Leiste: „Alle", favorisierte Ligen und favorisierte Teams als Chips.
class _FavoritesBar extends StatelessWidget {
  const _FavoritesBar({
    required this.leagueIds,
    required this.favTeams,
    required this.filter,
    required this.onSelect,
    required this.onLeagueTap,
  });

  final List<String> leagueIds;
  final List<Favorite> favTeams;
  final _Filter? filter;
  final ValueChanged<_Filter?> onSelect;
  final ValueChanged<String> onLeagueTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _BarChip(
              label: 'Alle',
              selected: filter == null,
              onTap: () => onSelect(null),
            ),
            // Liga-Chips öffnen die Liga-Übersicht (Tabelle + Spieltage),
            // sie filtern nicht — der Live-Feed zeigt immer alle Favoriten-Ligen.
            for (final id in leagueIds)
              _BarChip(
                label: Leagues.byId(id).name,
                icon: Icons.emoji_events_outlined,
                selected: false,
                trailingChevron: true,
                onTap: () => onLeagueTap(id),
              ),
            for (final t in favTeams)
              _BarChip(
                label: t.shortName ?? t.label,
                team: TeamRef(
                  id: t.key,
                  name: t.label,
                  shortName: t.shortName ?? t.label,
                  iconUrl: t.iconUrl,
                ),
                selected:
                    filter?.type == FavoriteType.team && filter?.key == t.key,
                onTap: () => onSelect(_Filter(FavoriteType.team, t.key)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.team,
    this.trailingChevron = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final TeamRef? team;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget leading = team != null
        ? TeamBadge(team: team!)
        : Icon(icon ?? Icons.tune,
            size: 18,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: Material(
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                  if (trailingChevron) ...[
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right,
                        size: 16, color: scheme.onSurfaceVariant),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.item});
  final _LiveItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = item.fixture;
    final live = f.status == FixtureStatus.live;
    final finished = f.status == FixtureStatus.finished;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            _LeagueTag(leagueId: item.league.id),
            const SizedBox(width: 6),
            Expanded(child: _TeamSide(team: f.home)),
            SizedBox(
              width: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f.hasScore)
                    Text('${f.homeScore}:${f.awayScore}',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: live ? MatchUpColors.red : scheme.onSurface))
                  else
                    Text(DateFormat('HH:mm').format(f.kickoff.toLocal()),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  if (live)
                    const Text('● LIVE',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: MatchUpColors.red))
                  else
                    Text(finished ? 'beendet' : 'Anstoß',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Expanded(child: _TeamSide(team: f.away, alignEnd: true)),
          ],
        ),
      ),
    );
  }
}

class _LeagueTag extends StatelessWidget {
  const _LeagueTag({required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final short = switch (leagueId) {
      'wm2026' => 'WM',
      'bundesliga' => 'BL',
      _ => leagueId.length >= 2 ? leagueId.substring(0, 2).toUpperCase() : '?',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(short,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant)),
    );
  }
}

class _TeamSide extends StatelessWidget {
  const _TeamSide({required this.team, this.alignEnd = false});
  final TeamRef team;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final badge = TeamBadge(team: team);
    final label = Flexible(
      child: Text(team.shortName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [label, const SizedBox(width: 8), badge]
          : [badge, const SizedBox(width: 8), label],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
          child: Column(
            children: [
              Icon(Icons.event_busy,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
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
