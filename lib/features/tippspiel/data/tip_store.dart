import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tip.dart';

/// Ablage für die eigenen Tipps. Zwei Implementierungen:
/// [LocalTipStore] (Gerät, ohne Konto) und [SupabaseTipStore]
/// (Tipprunde auf dem Server, Deadline per RLS erzwungen).
abstract class TipStore {
  Future<Map<String, Tip>> load();
  Future<void> save(Tip tip);
  Future<void> remove(String fixtureId);
}

/// Wird geworfen, wenn der Server einen Tipp ablehnt — praktisch immer,
/// weil die Tippfrist (Anstoß) vorbei ist.
class TipRejected implements Exception {
  const TipRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class SupabaseTipStore implements TipStore {
  SupabaseTipStore(this._client, this.roundId);

  final SupabaseClient _client;
  final String roundId;

  String get _userId => _client.auth.currentUser!.id;

  @override
  Future<Map<String, Tip>> load() async {
    final rows = await _client
        .from('tips')
        .select('fixture_id, home_goals, away_goals')
        .eq('round_id', roundId)
        .eq('user_id', _userId);
    return {
      for (final row in rows)
        row['fixture_id'] as String: Tip(
          fixtureId: row['fixture_id'] as String,
          homeGoals: row['home_goals'] as int,
          awayGoals: row['away_goals'] as int,
        ),
    };
  }

  @override
  Future<void> save(Tip tip) async {
    try {
      await _upsert(tip);
    } on PostgrestException catch (e) {
      // 42501 (RLS) bzw. 23503 (Fremdschlüssel) können auch daran liegen,
      // dass das Spiel in der App schon sichtbar, serverseitig aber noch
      // nicht gespiegelt ist (Sync läuft nur alle ~10 Min). In dem Fall
      // den Sync einmal anstoßen und erneut speichern — sonst geht ein vor
      // Anstoß abgegebener Tipp unbemerkt verloren.
      if ((e.code == '42501' || e.code == '23503') &&
          !await _isFixtureMirrored(tip.fixtureId)) {
        await _triggerSync();
        try {
          await _upsert(tip);
          return;
        } on PostgrestException catch (retryError) {
          throw _rejected(retryError);
        }
      }
      throw _rejected(e);
    }
  }

  Future<void> _upsert(Tip tip) => _client.from('tips').upsert({
        'round_id': roundId,
        'user_id': _userId,
        'fixture_id': tip.fixtureId,
        'home_goals': tip.homeGoals,
        'away_goals': tip.awayGoals,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  /// Steht das Spiel schon in der gespiegelten `fixtures`-Tabelle? Wenn nicht,
  /// ist ein Fehlschlag vermutlich nur eine Sync-Lücke, kein echtes Aus.
  Future<bool> _isFixtureMirrored(String fixtureId) async {
    final row = await _client
        .from('fixtures')
        .select('id')
        .eq('id', fixtureId)
        .maybeSingle();
    return row != null;
  }

  /// Stößt den serverseitigen Fixture-Sync an (als eingeloggter Nutzer
  /// erlaubt). Fehler hier werden geschluckt — der anschließende erneute
  /// Speicherversuch meldet das eigentliche Ergebnis.
  Future<void> _triggerSync() async {
    try {
      await _client.functions.invoke('sync-fixtures');
    } catch (_) {/* Retry meldet das Ergebnis */}
  }

  // 42501 = RLS-Verstoß: Tippfrist abgelaufen oder kein Mitglied.
  // 23503 = Fixture (noch) nicht in der Datenbank gespiegelt.
  TipRejected _rejected(PostgrestException e) => TipRejected(switch (e.code) {
        '42501' => 'Tippfrist abgelaufen — das Spiel hat schon begonnen.',
        '23503' =>
          'Dieses Spiel ist noch nicht synchronisiert. Versuch es gleich nochmal.',
        _ => 'Tipp konnte nicht gespeichert werden: ${e.message}',
      });

  @override
  Future<void> remove(String fixtureId) async {
    await _client.from('tips').delete().match({
      'round_id': roundId,
      'user_id': _userId,
      'fixture_id': fixtureId,
    });
  }
}
