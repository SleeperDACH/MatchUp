import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../auth/providers.dart';

/// **Live-Push für Vereine und ganze Ligen, unabhängig von den Favoriten**
/// (20.10.2026, Migration 0142). Favoriten melden weiter von selbst; ein Abo
/// kommt dazu. Welche Sorten ankommen (Anpfiff, Tore, …), entscheiden für
/// alle Wege dieselben Schalter in `push_einstellungen`.
///
/// Schlüssel wie in der Datenbank: Vereine als `sportmonks:<id>` (dieselbe
/// Form wie `user_favorites.key` und `TeamRef.id`), Ligen als
/// `fixtures.league_id`.
class LiveAbos {
  const LiveAbos({this.vereine = const {}, this.ligen = const {}});

  final Set<String> vereine;
  final Set<String> ligen;

  /// Die Wettbewerbe, für die man abonnieren kann — dieselbe Liste prüft
  /// der Check `push_live_abos_liga_bekannt`.
  static const wettbewerbe = [
    Leagues.bundesliga,
    Leagues.bundesliga2,
    Leagues.liga3,
    Leagues.frauenBundesliga,
    Leagues.dfbPokal,
  ];

  bool get leer => vereine.isEmpty && ligen.isEmpty;

  LiveAbos mitVerein(String key, bool an) => LiveAbos(
        vereine: an ? {...vereine, key} : ({...vereine}..remove(key)),
        ligen: ligen,
      );

  LiveAbos mitLiga(String id, bool an) => LiveAbos(
        vereine: vereine,
        ligen: an ? {...ligen, id} : ({...ligen}..remove(id)),
      );

  /// „2 Vereine · 1 Liga", „Nur Favoriten".
  String get zusammenfassung {
    if (leer) return 'Nur Favoriten';
    final teile = <String>[
      if (vereine.isNotEmpty)
        vereine.length == 1 ? '1 Verein' : '${vereine.length} Vereine',
      if (ligen.isNotEmpty)
        ligen.length == 1 ? '1 Liga' : '${ligen.length} Ligen',
    ];
    return teile.join(' · ');
  }
}

class LiveAbosRepository {
  LiveAbosRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<LiveAbos> laden() async {
    final uid = _uid;
    if (uid == null) return const LiveAbos();
    final rows = await _client
        .from('push_live_abos')
        .select('art, schluessel')
        .eq('user_id', uid);
    final vereine = <String>{};
    final ligen = <String>{};
    for (final r in rows) {
      final k = r['schluessel'] as String;
      if (r['art'] == 'liga') {
        ligen.add(k);
      } else {
        vereine.add(k);
      }
    }
    return LiveAbos(vereine: vereine, ligen: ligen);
  }

  /// Eine Zeile je Abo — an heißt anlegen, aus heißt löschen. `upsert`, damit
  /// ein doppelter Tipp (oder ein zweites Gerät) nicht am Schlüssel scheitert.
  Future<void> setzen(String art, String schluessel, bool an) async {
    final uid = _uid;
    if (uid == null) return;
    if (an) {
      await _client.from('push_live_abos').upsert({
        'user_id': uid,
        'art': art,
        'schluessel': schluessel,
      }, onConflict: 'user_id,art,schluessel', ignoreDuplicates: true);
    } else {
      await _client
          .from('push_live_abos')
          .delete()
          .eq('user_id', uid)
          .eq('art', art)
          .eq('schluessel', schluessel);
    }
  }
}

final liveAbosRepositoryProvider = Provider<LiveAbosRepository>((ref) {
  return LiveAbosRepository(Supabase.instance.client);
});

/// Die Abos des angemeldeten Nutzers; im lokalen Modus keine.
final liveAbosProvider = FutureProvider<LiveAbos>((ref) async {
  if (!AppConfig.isSupabaseConfigured) return const LiveAbos();
  ref.watch(currentUserProvider);
  return ref.read(liveAbosRepositoryProvider).laden();
});
