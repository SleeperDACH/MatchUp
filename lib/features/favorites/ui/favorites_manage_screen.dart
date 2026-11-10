import 'package:flutter/material.dart';
import '../../../app/widgets/skelett.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/competition_emblem.dart';
import '../../../app/widgets/kapitelmarke.dart';
import '../../../app/widgets/league_logo.dart';
import '../../../core/models/models.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../favorites.dart';

/// Teams favorisieren: erst einen Wettbewerb wählen, dann in dessen Team-Liste
/// die gewünschten Teams mit dem Stern markieren. Wird vom Favoriten-Tab über
/// einen eigenen Button geöffnet.
class FavoritesManageScreen extends ConsumerWidget {
  const FavoritesManageScreen({super.key});

  // Wettbewerbe, aus denen Teams favorisiert werden können (echte Ligen —
  // der DFB-Pokal wäre teamübergreifend gemischt).
  static const _leagues = [
    Leagues.bundesliga,
    Leagues.bundesliga2,
    Leagues.liga3,
    Leagues.frauenBundesliga,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriten = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Team favorisieren')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              'Wähle einen Wettbewerb und markiere darin deine Teams mit dem '
              'Stern.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          for (final league in _leagues)
            Card(
              child: ListTile(
                leading: LeagueLogo(
                  leagueId: league.id,
                  size: 38,
                  fallback: CompetitionEmblem(leagueId: league.id, size: 38),
                ),
                title: Text(league.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _LeagueTeamsPicker(league: league))),
              ),
            ),
          // **Nationalmannschaften** (10.11.2026, auf Ansage): direkt mit
          // Stern, ohne Zwischenschirm — es gibt (noch) nur eine.
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Kapitelmarke('Nationalmannschaften'),
          ),
          for (final nation in nationen)
            Builder(builder: (context) {
              final fav = Favorite.nation(nation);
              final an = favoriten.any((f) => f.key == fav.key);
              return Card(
                child: ListTile(
                  leading: LeagueLogo(
                    leagueId: nation.id,
                    size: 38,
                    fallback: CompetitionEmblem(leagueId: nation.id, size: 38),
                  ),
                  title: Text(nation.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Alle Länderspiele'),
                  trailing: IconButton(
                    tooltip: an
                        ? '${nation.name} aus Favoriten entfernen'
                        : '${nation.name} zu Favoriten hinzufügen',
                    icon: Icon(
                      an ? Icons.star : Icons.star_border,
                      color: an ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    onPressed: () => notifier.toggle(fav),
                  ),
                  onTap: () => notifier.toggle(fav),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Team-Liste eines Wettbewerbs mit Stern-Umschalter je Team.
class _LeagueTeamsPicker extends ConsumerWidget {
  const _LeagueTeamsPicker({required this.league});

  final LeagueInfo league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final teamsAsync = ref.watch(leaguePickerTeamsProvider(league.id));
    final favorites = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(league.name)),
      body: teamsAsync.when(
        loading: () => const Skelett(),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Teams konnten nicht geladen werden.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ),
        data: (teams) {
          if (teams.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Noch keine Teams verfügbar (Spielplan noch nicht '
                  'veröffentlicht).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 32),
            itemCount: teams.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
            itemBuilder: (context, i) {
              final team = teams[i];
              final isFav = isTeamFavorited(favorites, team.id);
              return ListTile(
                leading: TeamBadge(team: team),
                title: Text(team.name),
                trailing: IconButton(
                  // Der Name nennt Verein und Richtung: In einer Liste von
                  // 18 gleich aussehenden Zeilen sagte „Schaltfläche" weder,
                  // zu wem der Stern gehört, noch ob er gerade gesetzt ist —
                  // gefüllt oder umrandet ist ein rein bildlicher
                  // Unterschied.
                  tooltip: isFav
                      ? '${team.name} aus Favoriten entfernen'
                      : '${team.name} zu Favoriten hinzufügen',
                  icon: Icon(
                    isFav ? Icons.star : Icons.star_border,
                    color: isFav ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  onPressed: () =>
                      notifier.toggle(Favorite.team(team, league.id)),
                ),
                onTap: () => notifier.toggle(Favorite.team(team, league.id)),
              );
            },
          );
        },
      ),
    );
  }
}
