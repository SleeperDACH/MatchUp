import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../app/widgets/competition_emblem.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../favorites.dart';

/// Favoriten verwalten: Ligen folgen + Teams (Vereine/Länder) favorisieren.
/// Die Auswahl steuert Anzeige und Filter im Live-Tab.
class FavoritesSettingsScreen extends ConsumerWidget {
  const FavoritesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Favoriten')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          const _GroupLabel('Ligen'),
          Card(
            child: Column(
              children: [
                for (final league in Leagues.all)
                  SwitchListTile(
                    value: favorites.any((f) =>
                        f.type == FavoriteType.league && f.key == league.id),
                    onChanged: (_) => notifier.toggle(Favorite.league(league)),
                    title: Text(league.name),
                    secondary: CompetitionEmblem(leagueId: league.id, size: 34),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final league in Leagues.all) ...[
            _GroupLabel(_teamSectionTitle(league)),
            _TeamList(league: league),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _teamSectionTitle(LeagueInfo league) =>
      league.id == 'wm2026' ? 'Länder · ${league.name}' : 'Vereine · ${league.name}';
}

class _TeamList extends ConsumerWidget {
  const _TeamList({required this.league});

  final LeagueInfo league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(leagueTeamsProvider(league.id));
    final favorites = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return teamsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Teams für ${league.name} konnten nicht geladen werden.',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ),
      data: (teams) {
        if (teams.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Noch keine Teams für ${league.name} verfügbar '
                '(Spielplan noch nicht veröffentlicht).',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (final team in teams)
                ListTile(
                  leading: TeamBadge(team: team),
                  title: Text(team.name),
                  trailing: IconButton(
                    icon: Icon(
                      favorites.any((f) =>
                              f.type == FavoriteType.team && f.key == team.id)
                          ? Icons.star
                          : Icons.star_border,
                      color: favorites.any((f) =>
                              f.type == FavoriteType.team && f.key == team.id)
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    onPressed: () =>
                        notifier.toggle(Favorite.team(team, league.id)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
