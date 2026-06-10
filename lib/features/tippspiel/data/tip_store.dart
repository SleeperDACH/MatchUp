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
      await _client.from('tips').upsert({
        'round_id': roundId,
        'user_id': _userId,
        'fixture_id': tip.fixtureId,
        'home_goals': tip.homeGoals,
        'away_goals': tip.awayGoals,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on PostgrestException catch (e) {
      // 42501 = RLS-Verstoß: Tippfrist abgelaufen oder kein Mitglied.
      // 23503 = Fixture (noch) nicht in der Datenbank gespiegelt.
      throw TipRejected(switch (e.code) {
        '42501' => 'Tippfrist abgelaufen — das Spiel hat schon begonnen.',
        '23503' =>
          'Dieses Spiel ist noch nicht synchronisiert. Versuch es gleich nochmal.',
        _ => 'Tipp konnte nicht gespeichert werden: ${e.message}',
      });
    }
  }

  @override
  Future<void> remove(String fixtureId) async {
    await _client.from('tips').delete().match({
      'round_id': roundId,
      'user_id': _userId,
      'fixture_id': fixtureId,
    });
  }
}
