import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/models/models.dart';
import '../auth/providers.dart';
import '../tippspiel/providers.dart';

enum FavoriteType { team, league }

/// Ein favorisiertes Team (Verein/Land) oder eine favorisierte Liga.
/// Liegt in Supabase (`user_favorites`), synct über das Konto.
class Favorite {
  const Favorite({
    required this.type,
    required this.key,
    required this.label,
    this.leagueId,
    this.shortName,
    this.iconUrl,
  });

  final FavoriteType type;

  /// Stabiler Schlüssel: `team.id` bzw. `league.id`.
  final String key;
  final String label;
  final String? leagueId;
  final String? shortName;
  final String? iconUrl;

  factory Favorite.team(TeamRef team, String leagueId) => Favorite(
        type: FavoriteType.team,
        key: team.id,
        label: team.name,
        leagueId: leagueId,
        shortName: team.shortName,
        iconUrl: team.iconUrl,
      );

  factory Favorite.league(LeagueInfo league) => Favorite(
        type: FavoriteType.league,
        key: league.id,
        label: league.name,
      );

  factory Favorite.fromRow(Map<String, dynamic> r) => Favorite(
        type: r['fav_type'] == 'league' ? FavoriteType.league : FavoriteType.team,
        key: r['key'] as String,
        label: r['label'] as String,
        leagueId: r['league_id'] as String?,
        shortName: r['short_name'] as String?,
        iconUrl: r['icon_url'] as String?,
      );

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'fav_type': type.name,
        'key': key,
        'label': label,
        'league_id': leagueId,
        'short_name': shortName,
        'icon_url': iconUrl,
      };
}

class FavoritesRepository {
  FavoritesRepository(this._client);
  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<List<Favorite>> load() async {
    final rows = await _client
        .from('user_favorites')
        .select()
        .eq('user_id', _uid)
        .order('created_at');
    return [for (final r in rows) Favorite.fromRow(r)];
  }

  Future<void> add(Favorite fav) =>
      _client.from('user_favorites').upsert(fav.toRow(_uid));

  Future<void> remove(FavoriteType type, String key) => _client
      .from('user_favorites')
      .delete()
      .match({'user_id': _uid, 'fav_type': type.name, 'key': key});
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
    (ref) => FavoritesRepository(Supabase.instance.client));

/// Favoriten des angemeldeten Nutzers (leere Liste, solange niemand
/// angemeldet ist). Optimistisches Umschalten mit Persistenz.
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Favorite>>((ref) {
  final user = ref.watch(currentUserProvider);
  return FavoritesNotifier(
      ref.read(favoritesRepositoryProvider), enabled: user != null);
});

class FavoritesNotifier extends StateNotifier<List<Favorite>> {
  FavoritesNotifier(this._repo, {required bool enabled}) : super(const []) {
    if (enabled) _load();
  }

  final FavoritesRepository _repo;

  Future<void> _load() async {
    try {
      state = await _repo.load();
    } catch (_) {/* offline o.ä. — bleibt leer */}
  }

  bool isFavorite(FavoriteType type, String key) =>
      state.any((f) => f.type == type && f.key == key);

  Future<void> toggle(Favorite fav) async {
    final exists = isFavorite(fav.type, fav.key);
    final previous = state;
    state = exists
        ? [
            for (final f in state)
              if (!(f.type == fav.type && f.key == fav.key)) f
          ]
        : [...state, fav];
    try {
      if (exists) {
        await _repo.remove(fav.type, fav.key);
      } else {
        await _repo.add(fav);
      }
    } catch (_) {
      state = previous; // bei Fehler zurückrollen
    }
  }
}

/// Teams einer Liga (für die Favoriten-Auswahl), abgeleitet aus dem
/// Saison-Spielplan und nach Name sortiert.
final leagueTeamsProvider =
    Provider.family<AsyncValue<List<TeamRef>>, String>((ref, leagueId) {
  return ref.watch(leagueSeasonFixturesProvider(leagueId)).whenData((fixtures) {
    final byId = <String, TeamRef>{};
    for (final f in fixtures) {
      if (!isPlaceholderTeam(f.home)) byId[f.home.id] = f.home;
      if (!isPlaceholderTeam(f.away)) byId[f.away.id] = f.away;
    }
    final teams = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return teams;
  });
});

/// Platzhalter-„Teams" der K.-o.-Runde sind keine echten Mannschaften und
/// gehören nicht in die Favoritenauswahl: Sieger-Paarungen („ARG/CPV") oder
/// Gruppen-Platzierungen („2H", „1A"). Echte Team-/Ländernamen enthalten
/// kein „/" und beginnen nicht mit einer Ziffer.
bool isPlaceholderTeam(TeamRef team) {
  final name = team.name.trim();
  return name.contains('/') ||
      team.shortName.contains('/') ||
      RegExp(r'^\d').hasMatch(name);
}
