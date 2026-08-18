import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/data/sportmonks/sportmonks_provider.dart';
import '../../core/models/squad_member.dart';
import '../../core/models/models.dart';
import '../../core/models/team_fixture.dart';
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
    this.sortOrder,
  });

  final FavoriteType type;

  /// Stabiler Schlüssel: `team.id` bzw. `league.id`.
  final String key;
  final String label;
  final String? leagueId;
  final String? shortName;
  final String? iconUrl;

  /// Manuelle Sortierposition (null = noch nie manuell sortiert).
  final int? sortOrder;

  Favorite copyWith({int? sortOrder}) => Favorite(
        type: type,
        key: key,
        label: label,
        leagueId: leagueId,
        shortName: shortName,
        iconUrl: iconUrl,
        sortOrder: sortOrder ?? this.sortOrder,
      );

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
        sortOrder: (r['sort_order'] as num?)?.toInt(),
      );

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'fav_type': type.name,
        'key': key,
        'label': label,
        'league_id': leagueId,
        'short_name': shortName,
        'icon_url': iconUrl,
        'sort_order': sortOrder,
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
        .order('sort_order', nullsFirst: false)
        .order('created_at');
    return [for (final r in rows) Favorite.fromRow(r)];
  }

  Future<void> add(Favorite fav) =>
      _client.from('user_favorites').upsert(fav.toRow(_uid));

  Future<void> remove(FavoriteType type, String key) => _client
      .from('user_favorites')
      .delete()
      .match({'user_id': _uid, 'fav_type': type.name, 'key': key});

  /// Neue manuelle Reihenfolge speichern (sort_order = Position).
  Future<void> reorder(List<Favorite> ordered) async {
    final rows = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(sortOrder: i).toRow(_uid)
    ];
    await _client.from('user_favorites').upsert(rows);
  }
}

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
    (ref) => FavoritesRepository(Supabase.instance.client));

/// Favoriten des angemeldeten Nutzers (leere Liste, solange niemand
/// angemeldet ist). Optimistisches Umschalten mit Persistenz.
///
/// Das Repository wird **nur** angelegt, wenn der Server auch erreichbar ist:
/// `FavoritesRepository(Supabase.instance.client)` wirft sonst eine Assertion,
/// und zwar mitten im Aufbau des Favoriten-Tabs. Vorher lief `ref.read` immer
/// — im Release-Build war der Tab dadurch eine graue Fläche, sobald die App
/// ohne Server-Verbindung lief (genau der erste TestFlight-Build).
/// `enabled` prüft deshalb beides: Server da *und* jemand angemeldet.
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Favorite>>((ref) {
  final enabled =
      AppConfig.isSupabaseConfigured && ref.watch(currentUserProvider) != null;
  return FavoritesNotifier(
      enabled ? ref.read(favoritesRepositoryProvider) : null);
});

class FavoritesNotifier extends StateNotifier<List<Favorite>> {
  FavoritesNotifier(this._repo) : super(const []) {
    if (_repo != null) _load();
  }

  /// `null` = kein Server oder niemand angemeldet; die Favoritenliste bleibt
  /// dann leer und Änderungen sind wirkungslos statt fehlerhaft.
  final FavoritesRepository? _repo;

  Future<void> _load() async {
    try {
      state = await _repo!.load();
    } catch (_) {/* offline o.ä. — bleibt leer */}
  }

  bool isFavorite(FavoriteType type, String key) =>
      state.any((f) => f.type == type && f.key == key);

  Future<void> toggle(Favorite fav) async {
    final repo = _repo;
    if (repo == null) return;
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
        await repo.remove(fav.type, fav.key);
      } else {
        await repo.add(fav);
      }
    } catch (_) {
      state = previous; // bei Fehler zurückrollen
    }
  }

  /// Neue manuelle Reihenfolge übernehmen (optimistisch, mit Persistenz).
  Future<void> setManualOrder(List<Favorite> ordered) async {
    final repo = _repo;
    if (repo == null) return;
    final previous = state;
    state = [
      for (var i = 0; i < ordered.length; i++) ordered[i].copyWith(sortOrder: i)
    ];
    try {
      await repo.reorder(ordered);
    } catch (_) {
      state = previous;
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

/// Reine Sportmonks-Team-ID aus dem Favoriten-Schlüssel
/// (`sportmonks:503` → `503`). [teamFixturesProvider] und [teamSquadProvider]
/// erwarten sie **ohne** Präfix; mit Präfix liefert die Function nichts und
/// der Aufrufer sieht nur eine leere Liste. Steht hier und nicht als Kopie in
/// den Aufrufern, weil genau das schon zweimal passiert ist.
String teamIdOf(String favoriteKey) => favoriteKey.split(':').last;

/// Spielplan eines favorisierten Teams (wettbewerbsübergreifend). Family-Key
/// ist die reine Sportmonks-Team-ID ([teamIdOf]). Braucht die
/// Server-Verbindung.
final teamFixturesProvider =
    FutureProvider.family<List<TeamFixture>, String>((ref, teamId) {
  if (!AppConfig.isSupabaseConfigured) return Future.value(const []);
  return SupabaseSportmonksProvider().getTeamFixtures(teamId);
});

/// Kader eines Vereins. Family-Key ist die reine Sportmonks-Team-ID.
/// Braucht die Server-Verbindung; der Kader wird serverseitig einen Tag
/// gecacht (er ändert sich nur bei Transfers).
final teamSquadProvider =
    FutureProvider.family<List<SquadMember>, String>((ref, teamId) {
  if (!AppConfig.isSupabaseConfigured) return Future.value(const []);
  return SupabaseSportmonksProvider().getSquad(teamId);
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
