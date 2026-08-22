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

  /// **Alle** gespeicherten Zeilen zu Typ und Schlüssel — bei Teams über die
  /// reine Team-ID ([teamIdOf]) verglichen. Mehrzahl mit Absicht: Zu einem
  /// Verein können mehrere Zeilen mit unterschiedlichem Schlüssel-Präfix
  /// liegen (`503`, `sportmonks:503`, `openligadb:503`). Traf der Stern nur
  /// eine davon, blieb die andere liegen — im Favoriten-Tab stand dann weiter
  /// das Wappen, während Spielplan und News leer waren, weil die alte ID bei
  /// Sportmonks nichts liefert.
  List<Favorite> findAll(FavoriteType type, String key) =>
      [for (final f in state) if (matchesFavorite(f, type, key)) f];

  bool isFavorite(FavoriteType type, String key) =>
      findAll(type, key).isNotEmpty;

  Future<void> toggle(Favorite fav) async {
    final repo = _repo;
    if (repo == null) return;
    // Gelöscht wird mit dem Schlüssel der **gespeicherten** Zeilen: mit dem
    // übergebenen traf das Delete bei abweichendem Präfix keine Zeile, der
    // Favorit verschwand kurz und war nach dem nächsten Laden wieder da.
    final vorhanden = findAll(fav.type, fav.key);
    final previous = state;
    state = vorhanden.isNotEmpty
        ? [
            for (final f in state)
              if (!vorhanden.any((v) => v.type == f.type && v.key == f.key)) f
          ]
        : [...state, fav];
    try {
      if (vorhanden.isNotEmpty) {
        for (final v in vorhanden) {
          await repo.remove(v.type, v.key);
        }
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

/// Teams für die Favoriten-**Auswahl**: die Teams der Liga plus die bereits
/// gespeicherten Favoriten derselben Liga, auch wenn sie im aktuellen
/// Spielplan fehlen (Verein abgestiegen, Spielplan noch nicht veröffentlicht,
/// alt gespeicherter Schlüssel). Ohne sie stand so ein Favorit weiter im
/// Favoriten-Tab, ließ sich aber nirgends abwählen — den Stern dazu gab es
/// schlicht nicht. Bewusst getrennt von [leagueTeamsProvider], das die Frage
/// „wer spielt in dieser Liga" beantwortet (u. a. für die Tabellen-Zuordnung
/// im Vereins-Screen) und diese Nachzügler deshalb nicht enthalten darf.
final leaguePickerTeamsProvider =
    Provider.family<AsyncValue<List<TeamRef>>, String>((ref, leagueId) {
  final favs = ref.watch(favoritesProvider);
  return ref.watch(leagueTeamsProvider(leagueId)).whenData((teams) {
    final bekannt = {for (final t in teams) teamIdOf(t.id)};
    final ergaenzt = [...teams];
    for (final f in favs) {
      if (f.type != FavoriteType.team || f.leagueId != leagueId) continue;
      if (!bekannt.add(teamIdOf(f.key))) continue;
      ergaenzt.add(TeamRef(
        id: f.key,
        name: f.label,
        shortName: f.shortName ?? f.label,
        iconUrl: f.iconUrl,
      ));
    }
    if (ergaenzt.length == teams.length) return teams;
    return ergaenzt
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  });
});

/// Lässt sich zu diesem Team-Favoriten überhaupt etwas laden? Spielplan und
/// News laufen über Sportmonks; ein Schlüssel aus einer früheren Quelle
/// (`openligadb:100`) trifft dort nichts. Solche Zeilen dürfen nicht angezeigt
/// werden — sonst steht ihr Wappen im Favoriten-Tab, während darunter alles
/// leer bleibt. Migration `0075_favorites_drop_openligadb.sql` löscht die
/// Bestandszeilen; diese Prüfung hält die Anzeige auch ohne sie richtig.
bool isResolvableTeamFavorite(Favorite f) =>
    f.type != FavoriteType.team || f.key.startsWith('sportmonks:');

/// Meint dieser Favorit denselben Eintrag? Bei Teams über die reine Team-ID
/// ([teamIdOf]), damit ein abweichendes Schlüssel-Präfix denselben Verein
/// bezeichnet. Einzige Vergleichsstelle — Stern-Anzeige und Löschen dürfen
/// nicht auseinanderlaufen, sonst leuchtet der Stern an einer Zeile, die der
/// Klick nicht trifft.
bool matchesFavorite(Favorite f, FavoriteType type, String key) =>
    f.type == type &&
    (type == FavoriteType.team
        ? teamIdOf(f.key) == teamIdOf(key)
        : f.key == key);

/// Ist dieses Team favorisiert? (Stern in der Favoritenauswahl.)
bool isTeamFavorited(List<Favorite> favs, String teamId) =>
    favs.any((f) => matchesFavorite(f, FavoriteType.team, teamId));

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
