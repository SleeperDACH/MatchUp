import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/models/models.dart';
import '../models/chat_message.dart';
import '../models/tip.dart';
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
    ScoringRules rules = ScoringRules.kicktippDefault,
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
          'scoring': rules.toJson(),
        })
        .select()
        .single();
    return TipRound.fromJson(row);
  }

  /// Aktualisiert Wertung & Modi einer Runde (nur der Ersteller, per RLS).
  Future<void> updateScoring(String roundId, ScoringRules rules) => _client
      .from('tip_rounds')
      .update({'scoring': rules.toJson()}).eq('id', roundId);

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
        .select('user_id, team_name, profiles(username)')
        .eq('round_id', roundId);
    return rows.map(RoundMember.fromJson).toList();
  }

  /// Setzt den eigenen ligaspezifischen Teamnamen (leer = löschen). Nur der
  /// eigene Eintrag wird geändert (RPC, security definer).
  Future<void> setTeamName(String roundId, String name) => _client.rpc(
      'tip_set_team_name', params: {'p_round_id': roundId, 'p_name': name});

  /// Alle für mich sichtbaren Tipps der Liga: eigene immer, fremde
  /// erst nach Anstoß (erzwingt die RLS-Policy serverseitig).
  Future<List<MemberTip>> allTips(String roundId) async {
    final rows = await _client
        .from('tips')
        .select('user_id, fixture_id, home_goals, away_goals')
        .eq('round_id', roundId);
    return rows.map(MemberTip.fromJson).toList();
  }

  /// Existenz-Auskunft: Set aus `userId|fixtureId` aller bereits abgegebenen
  /// Tipps der Runde — ohne die Tipp-Werte. Für das Schloss-Symbol vor
  /// Anstoß (Gegner hat getippt). Serverseitig nur für Mitglieder.
  Future<Set<String>> tipPresence(String roundId) async {
    final rows = await _client
        .rpc('round_tip_presence', params: {'p_round_id': roundId}) as List;
    return {
      for (final r in rows)
        '${(r as Map)['user_id']}|${r['fixture_id']}',
    };
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
  Future<void> sendMessage(String roundId, String body,
      {String? replyTo}) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('tip_round_messages').insert({
      'round_id': roundId,
      'user_id': userId,
      'body': body.trim(),
      'reply_to': ?replyTo,
    });
  }

  /// Löscht eine Tipprunde endgültig (nur der Ersteller, per RLS). Mitglieder,
  /// Tipps und Chat gehen per Cascade mit.
  Future<void> deleteRound(String roundId) =>
      _client.from('tip_rounds').delete().eq('id', roundId);

  /// Benennt eine Tipprunde um (nur der Ersteller, per RLS). 3–64 Zeichen.
  Future<void> renameRound(String roundId, String name) =>
      _client.from('tip_rounds').update({'name': name.trim()}).eq('id', roundId);

  /// Alle abgegebenen Bonustipp-Antworten der Runde (RLS: nur Mitglieder).
  Future<List<BonusAnswer>> bonusAnswers(String roundId) async {
    final rows = await _client
        .from('tip_bonus_answers')
        .select('user_id, question, team_id, team_name')
        .eq('round_id', roundId);
    return rows.map(BonusAnswer.fromJson).toList();
  }

  /// Setzt die eigenen Team-Antworten einer Bonustipp-Frage (ersetzt die
  /// bisherigen — für „Absteiger" können es zwei Teams sein). Die Deadline
  /// (vor dem ersten Spieltag) erzwingt die RLS serverseitig.
  Future<void> setBonusAnswers({
    required String roundId,
    required String question,
    required List<({String id, String name})> teams,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client
        .from('tip_bonus_answers')
        .delete()
        .eq('round_id', roundId)
        .eq('user_id', userId)
        .eq('question', question);
    if (teams.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await _client.from('tip_bonus_answers').insert([
      for (final t in teams)
        {
          'round_id': roundId,
          'user_id': userId,
          'question': question,
          'team_id': t.id,
          'team_name': t.name,
          'updated_at': now,
        },
    ]);
  }
}
