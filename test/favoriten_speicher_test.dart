import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/favorites/favorites.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Favoriten liegen auch auf dem Gerät (07.11.2026, auf Ansage: „die
/// Favoriten lokal zu speichern sollte allgemein von Vorteil sein"). Beim
/// Start steht der gespeicherte Stand sofort da, der Server zieht nach.

class _Server extends FavoritesRepository {
  _Server(this.antwort)
    : super(
        SupabaseClient(
          'https://x.supabase.co',
          'k',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  /// Hält die Antwort zurück, bis der Test sie freigibt.
  final Completer<List<Favorite>> antwort;

  @override
  Future<List<Favorite>> load() => antwort.future;

  @override
  Future<void> add(Favorite fav) async {}
}

const _bayern = Favorite(
  type: FavoriteType.team,
  key: 'sportmonks:503',
  label: 'FC Bayern München',
);
const _schalke = Favorite(
  type: FavoriteType.team,
  key: 'sportmonks:67',
  label: 'Schalke 04',
);

Future<void> _warte() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('gespeicherter Stand steht da, bevor der Server antwortet', () async {
    await favoritenSpeichern('u1', [_bayern]);
    final server = Completer<List<Favorite>>();
    final n = FavoritesNotifier(_Server(server), userId: 'u1');
    await _warte();
    expect(n.state.map((f) => f.key), ['sportmonks:503']);
    expect(n.fertig, isTrue, reason: 'der Ladeschirm muss nicht warten');
    expect(n.geladen, isTrue);
  });

  test('der Server gewinnt und wird gespeichert', () async {
    await favoritenSpeichern('u1', [_bayern]);
    final server = Completer<List<Favorite>>();
    final n = FavoritesNotifier(_Server(server), userId: 'u1');
    await _warte();
    server.complete([_bayern, _schalke]);
    await _warte();
    expect(n.state.length, 2);
    final gespeichert = await favoritenAusSpeicher('u1');
    expect(gespeichert!.map((f) => f.key), ['sportmonks:503', 'sportmonks:67']);
  });

  test('gleiche Antwort setzt den Zustand nicht neu', () async {
    // Sonst lüde alles, was an den Vereinen hängt, ein zweites Mal.
    await favoritenSpeichern('u1', [_bayern]);
    final server = Completer<List<Favorite>>();
    final n = FavoritesNotifier(_Server(server), userId: 'u1');
    await _warte();
    final vorher = n.state;
    server.complete([_bayern]);
    await _warte();
    expect(identical(n.state, vorher), isTrue);
  });

  test('ohne Netz bleibt der gespeicherte Stand', () async {
    await favoritenSpeichern('u1', [_bayern]);
    final server = Completer<List<Favorite>>();
    final n = FavoritesNotifier(_Server(server), userId: 'u1');
    await _warte();
    server.completeError(Exception('offline'));
    await _warte();
    expect(n.state.map((f) => f.key), ['sportmonks:503']);
  });

  test('ein anderes Konto sieht nichts davon', () async {
    await favoritenSpeichern('u1', [_bayern]);
    expect(await favoritenAusSpeicher('u2'), isNull);
  });

  test('ohne Speicher wie bisher: erst der Server', () async {
    final server = Completer<List<Favorite>>();
    final n = FavoritesNotifier(_Server(server), userId: 'u1');
    await _warte();
    expect(n.fertig, isFalse);
    server.complete([_schalke]);
    await _warte();
    expect(n.state.map((f) => f.key), ['sportmonks:67']);
    expect((await favoritenAusSpeicher('u1'))!.length, 1);
  });
}
