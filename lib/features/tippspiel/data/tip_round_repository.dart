import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/models/models.dart';
import '../models/chat_message.dart';
import '../models/tip_round.dart';

/// Tipprunden-Verwaltung gegen Supabase. RLS sorgt dafür, dass nur die
/// eigenen Runden sichtbar sind.
class TipRoundRepository {
  TipRoundRepository(this._client);

  final SupabaseClient _client;

  Future<List<TipRound>> myRounds() async {
    final rows = await _client
        .from('tip_rounds')
        .select()
        .order('created_at', ascending: false);
    return rows.map(TipRound.fromJson).toList();
  }

  Future<TipRound> createRound({
    required String name,
    required LeagueInfo league,
    required int season,
  }) async {
    final userId = _client.auth.currentUser!.id;
    // Der Trigger tip_rounds_add_creator macht den Ersteller automatisch
    // zum Mitglied.
    final row = await _client
        .from('tip_rounds')
        .insert({
          'name': name.trim(),
          'league_id': league.id,
          'season': season,
          'created_by': userId,
        })
        .select()
        .single();
    return TipRound.fromJson(row);
  }

  Future<TipRound> joinRound(String inviteCode) async {
    final roundId = await _client.rpc<String>(
      'join_tip_round',
      params: {'p_invite_code': inviteCode.trim()},
    );
    final row =
        await _client.from('tip_rounds').select().eq('id', roundId).single();
    return TipRound.fromJson(row);
  }

  /// Alle Mitglieder der Liga — auch die, die noch keinen Tipp abgegeben
  /// haben (wichtig: neue Mitglieder sollen sofort sichtbar sein).
  Future<List<RoundMember>> members(String roundId) async {
    final rows = await _client
        .from('tip_round_members')
        .select('user_id, profiles(username)')
        .eq('round_id', roundId);
    return rows.map(RoundMember.fromJson).toList();
  }

  /// Alle für mich sichtbaren Tipps der Liga: eigene immer, fremde
  /// erst nach Anstoß (erzwingt die RLS-Policy serverseitig).
  Future<List<MemberTip>> allTips(String roundId) async {
    final rows = await _client
        .from('tips')
        .select('user_id, fixture_id, home_goals, away_goals')
        .eq('round_id', roundId);
    return rows.map(MemberTip.fromJson).toList();
  }

  /// Zum Anstoß eingefrorene Quoten je Fixture (für den Quoten-Bonus).
  /// Öffentlich lesbar; der Schlüssel ist die globale Fixture-ID, daher
  /// genügt ein Map über alle gespeicherten Spiele.
  Future<Map<String, FrozenOdds>> frozenOdds() async {
    final rows = await _client
        .from('fixture_odds')
        .select('fixture_id, home_win, draw, away_win');
    return {
      for (final r in rows) r['fixture_id'] as String: FrozenOdds.fromJson(r),
    };
  }

  /// Live-Stream der Chat-Nachrichten einer Liga (älteste zuerst). Läuft
  /// über Supabase Realtime; die RLS lässt nur Mitglieder mitlesen.
  Stream<List<ChatMessage>> messageStream(String roundId) {
    return _client
        .from('tip_round_messages')
        .stream(primaryKey: ['id'])
        .eq('round_id', roundId)
        // Älteste zuerst (Supabase sortiert sonst absteigend) — so stehen
        // neue Nachrichten unten.
        .order('created_at', ascending: true)
        .map((rows) => rows.map(ChatMessage.fromJson).toList());
  }

  /// Schreibt eine Nachricht in den Liga-Chat (nur als Mitglied erlaubt,
  /// erzwingt die RLS-Policy serverseitig).
  Future<void> sendMessage(String roundId, String body) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('tip_round_messages').insert({
      'round_id': roundId,
      'user_id': userId,
      'body': body.trim(),
    });
  }
}
