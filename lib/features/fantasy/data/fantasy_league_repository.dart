import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/chat_message.dart';
import '../../leagues/models/join_request.dart';
import '../models/fantasy_models.dart';
import '../models/trade.dart';

/// Dedupliziert Waiver-Anträge nach `id`. Der Supabase-Realtime-Stream kann
/// denselben Antrag doppelt liefern (Initial-Snapshot + Insert-Event); ohne
/// Dedup erschien er doppelt in der Liste und das zweite Stornieren schlug
/// fehl (Server: „Antrag nicht gefunden oder schon abgearbeitet"). Reihenfolge
/// bleibt erhalten (Map behält Einfüge-Reihenfolge).
List<WaiverClaim> dedupWaiverClaimsById(List<WaiverClaim> claims) {
  final byId = <String, WaiverClaim>{};
  for (final c in claims) {
    byId[c.id] = c;
  }
  return byId.values.toList();
}

/// Fantasy-Liga-Verwaltung gegen Supabase. RLS sorgt dafür, dass nur
/// die eigenen Ligen sichtbar sind.
class FantasyLeagueRepository {
  FantasyLeagueRepository(this._client);

  final SupabaseClient _client;

  Future<List<FantasyLeague>> myLeagues() async {
    final rows = await _client
        .from('fantasy_leagues')
        .select()
        .order('created_at', ascending: false);
    return rows.map(FantasyLeague.fromJson).toList();
  }

  Future<FantasyLeague> createLeague({
    required String name,
    required FantasyMode mode,
    required int season,
    required DraftPickTime pickTime,
    FantasyScoring scoring = FantasyScoring.kickbaseStyle,
    RosterConfig roster = RosterConfig.standard,
    int? maxTeams,
    String draftOrderMode = 'auto',
    int? pauseStart,
    int? pauseEnd,
    int? playoffTeams,
    int? playoffWeeks,
    int? tradeDeadlineOffset,
    String visibility = 'private',
    String joinPolicy = 'open',
    bool tipEnabled = false,
  }) async {
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('fantasy_leagues')
        .insert({
          'name': name.trim(),
          'mode': mode.name,
          'season': season,
          'draft_pick_seconds': pickTime.seconds,
          'scoring': scoring.toJson(),
          'roster': roster.toJson(),
          'created_by': userId,
          'max_teams': maxTeams,
          'draft_order_mode': draftOrderMode,
          'draft_pause_start': pauseStart,
          'draft_pause_end': pauseEnd,
          'playoff_teams': playoffTeams,
          'playoff_weeks': playoffWeeks,
          'trade_deadline_offset': tradeDeadlineOffset,
          'visibility': visibility,
          'join_policy': joinPolicy,
          'tip_enabled': tipEnabled,
        })
        .select()
        .single();
    return FantasyLeague.fromJson(row);
  }

  /// Schaltet das ligainterne Tippspiel für die Liga ein/aus (nur Ersteller,
  /// RLS). Steuert die Anzeige der Tippspiel-Option auf der Übersicht.
  Future<void> setTipEnabled(String leagueId, bool enabled) =>
      _client.from('fantasy_leagues').update({
        'tip_enabled': enabled,
      }).eq('id', leagueId);

  /// Löscht eine Fantasy-Liga endgültig (nur Ersteller, per RLS). Abhängige
  /// Daten (Mitglieder, Kader, Lineups, Waiver, Draft) gehen per Cascade mit.
  Future<void> deleteLeague(String leagueId) =>
      _client.from('fantasy_leagues').delete().eq('id', leagueId);

  /// Setzt das Liga-Logo (Bild-URL oder Emoji+Farbe; alles `null` = entfernen).
  /// Nur der Ersteller darf ändern (RLS).
  Future<void> setLogo(String leagueId,
          {String? url, String? emoji, String? color}) =>
      _client.from('fantasy_leagues').update({
        'logo_url': url,
        'logo_emoji': emoji,
        'logo_color': color,
      }).eq('id', leagueId);

  /// Ein Teilnehmer (nicht der Ersteller) verlässt die Liga; seine
  /// ligagebundenen Daten werden serverseitig entfernt.
  Future<void> leaveLeague(String leagueId) =>
      _client.rpc('leave_fantasy_league', params: {'p_league_id': leagueId});

  // --- Trades ---------------------------------------------------------

  /// Trade-Angebote der Liga in Echtzeit (RLS: nur eigene Beteiligung).
  Stream<List<TradeOffer>> tradesStream(String leagueId) => _client
      .from('fantasy_trades')
      .stream(primaryKey: ['id'])
      .eq('league_id', leagueId)
      .order('created_at')
      .map((rows) => rows.map(TradeOffer.fromJson).toList());

  /// Alle Positionen der eigenen Trades in Echtzeit (RLS-gefiltert), im
  /// Client per `trade_id` gruppiert.
  Stream<List<TradeItem>> tradeItemsStream() => _client
      .from('fantasy_trade_items')
      .stream(primaryKey: ['trade_id', 'player_id'])
      .map((rows) => rows.map(TradeItem.fromJson).toList());

  /// Erstellt ein Angebot und gibt dessen ID zurück (für die Chat-Verknüpfung).
  Future<String> proposeTrade(
    String leagueId,
    String toManager, {
    required List<String> offerPlayers,
    required List<String> requestPlayers,
    String? message,
    String? counterOf,
  }) async {
    final id = await _client.rpc('fantasy_propose_trade', params: {
      'p_league_id': leagueId,
      'p_to_manager': toManager,
      'p_offer_players': offerPlayers,
      'p_request_players': requestPlayers,
      'p_message': message,
      'p_counter_of': counterOf,
    });
    return id as String;
  }

  /// Einzelnes Angebot samt Positionen (für die Chat-Karte).
  Future<({TradeOffer trade, List<TradeItem> items})?> tradeById(
      String tradeId) async {
    final row = await _client
        .from('fantasy_trades')
        .select('*, fantasy_trade_items(giver, player_id)')
        .eq('id', tradeId)
        .maybeSingle();
    if (row == null) return null;
    final items = [
      for (final m in (row['fantasy_trade_items'] as List? ?? const []))
        TradeItem(
          tradeId: tradeId,
          giver: m['giver'] as String,
          playerId: m['player_id'] as String,
        )
    ];
    return (trade: TradeOffer.fromJson(row), items: items);
  }

  Future<void> respondTrade(String tradeId, bool accept) =>
      _client.rpc('fantasy_respond_trade',
          params: {'p_trade_id': tradeId, 'p_accept': accept});

  Future<void> cancelTrade(String tradeId) => _client
      .rpc('fantasy_cancel_trade', params: {'p_trade_id': tradeId});

  /// Ändert die Pickzeit nachträglich — nur vor dem Draft (Status `setup`).
  /// RLS erlaubt das Update nur dem Ersteller.
  Future<void> updatePickTime(String leagueId, DraftPickTime pickTime) =>
      _client
          .from('fantasy_leagues')
          .update({'draft_pick_seconds': pickTime.seconds})
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Draft-Einstellungen (Pickzeit, Runden über die roster-JSONB,
  /// Slow-Draft-Pause) — nur vor dem Draft (`.eq('draft_status','setup')`
  /// erzwingt das serverseitig; RLS erlaubt es nur dem Ersteller).
  Future<void> updateDraftSettings(
    String leagueId, {
    required DraftPickTime pickTime,
    required RosterConfig roster,
    required int? pauseStart,
    required int? pauseEnd,
    required String orderMode,
    int? u20Rounds,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({
            'draft_pick_seconds': pickTime.seconds,
            'roster': roster.toJson(),
            'draft_pause_start': pauseStart,
            'draft_pause_end': pauseEnd,
            'draft_order_mode': orderMode,
            'u20_rounds': ?u20Rounds,
          })
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Manuelle Draft-Reihenfolge setzen (Ersteller, nur im Setup). Die
  /// Positionen ergeben sich aus der Reihenfolge von [orderedUserIds].
  Future<void> setDraftOrder(String leagueId, List<String> orderedUserIds) =>
      _client.rpc('set_fantasy_draft_order', params: {
        'p_league_id': leagueId,
        'p_user_ids': orderedUserIds,
      });

  /// Liga umbenennen (nur der Ersteller, per RLS erzwungen). 3–64 Zeichen.
  Future<void> renameLeague(String leagueId, String name) => _client
      .from('fantasy_leagues')
      .update({'name': name.trim()})
      .eq('id', leagueId);

  /// Liga-Einstellungen (Teilnehmer-Limit) — ebenfalls nur vor dem Draft.
  Future<void> updateLeagueSettings(
    String leagueId, {
    required int? maxTeams,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({'max_teams': maxTeams})
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  /// Sichtbarkeit / Beitrittsmodus setzen (nur Ersteller, RLS). `private`
  /// ignoriert `joinPolicy`; wird der Konsistenz halber auf `open` gesetzt.
  Future<void> updateVisibility(
    String leagueId, {
    required String visibility,
    required String joinPolicy,
  }) =>
      _client.from('fantasy_leagues').update({
        'visibility': visibility,
        'join_policy': visibility == 'public' ? joinPolicy : 'open',
      }).eq('id', leagueId);

  /// Einzelne Liga laden (für Mitglieder per RLS lesbar).
  Future<FantasyLeague> fetchLeague(String leagueId) async {
    final row = await _client
        .from('fantasy_leagues')
        .select()
        .eq('id', leagueId)
        .single();
    return FantasyLeague.fromJson(row);
  }

  /// Freier Beitritt zu einer öffentlichen Liga (join_policy `open`).
  Future<FantasyLeague> joinPublic(String leagueId) async {
    final id = await _client
        .rpc<String>('join_public_fantasy_league', params: {'p_id': leagueId});
    final row =
        await _client.from('fantasy_leagues').select().eq('id', id).single();
    return FantasyLeague.fromJson(row);
  }

  /// Beitrittsanfrage an eine öffentliche Liga (join_policy `invite`).
  Future<void> requestJoin(String leagueId) => _client
      .rpc<void>('request_join_fantasy_league', params: {'p_id': leagueId});

  /// Offene Beitrittsanfragen einer Liga (nur für den Admin sichtbar, live).
  Stream<List<JoinRequest>> pendingRequests(String leagueId) => _client
      .from('fantasy_join_requests')
      .stream(primaryKey: ['league_id', 'user_id'])
      .eq('league_id', leagueId)
      .map((rows) => rows.map(JoinRequest.fromJson).toList());

  /// Anfrage annehmen (`accept: true`) oder ablehnen — nur Admin.
  Future<void> respondRequest(
    String leagueId,
    String userId, {
    required bool accept,
  }) =>
      _client.rpc<void>('respond_fantasy_join_request', params: {
        'p_league': leagueId,
        'p_user': userId,
        'p_accept': accept,
      });

  /// Playoff-Einstellungen (Teams, Wochen je Runde, Trade-Deadline-Offset) —
  /// nur vor dem Draft.
  Future<void> updatePlayoffSettings(
    String leagueId, {
    required int teams,
    required int weeks,
    required int tradeDeadlineOffset,
  }) =>
      _client
          .from('fantasy_leagues')
          .update({
            'playoff_teams': teams,
            'playoff_weeks': weeks,
            'trade_deadline_offset': tradeDeadlineOffset,
          })
          .eq('id', leagueId)
          .eq('draft_status', 'setup');

  Future<FantasyLeague> joinLeague(String inviteCode) async {
    final leagueId = await _client.rpc<String>(
      'join_fantasy_league',
      params: {'p_invite_code': inviteCode.trim()},
    );
    final row = await _client
        .from('fantasy_leagues')
        .select()
        .eq('id', leagueId)
        .single();
    return FantasyLeague.fromJson(row);
  }

  Future<List<FantasyManager>> managers(String leagueId) async {
    final rows = await _client
        .from('fantasy_league_members')
        .select('user_id, team_name, draft_position, waiver_priority, vacant, pending, auto_pick, profiles(username, avatar_url, avatar_emoji, avatar_color)')
        .eq('league_id', leagueId)
        .eq('vacant', false)
        .eq('pending', false)
        .order('joined_at');
    return rows.map(FantasyManager.fromJson).toList();
  }

  /// Verwaiste Teams (verlassen/gekickt) — der Admin kann sie neu zuweisen.
  Future<List<FantasyManager>> vacantTeams(String leagueId) async {
    final rows = await _client
        .from('fantasy_league_members')
        .select('user_id, team_name, draft_position, waiver_priority, vacant, pending, profiles(username, avatar_url, avatar_emoji, avatar_color)')
        .eq('league_id', leagueId)
        .eq('vacant', true)
        .order('joined_at');
    return rows.map(FantasyManager.fromJson).toList();
  }

  /// Nach Draft-Start beigetretene Mitglieder ohne Team; warten auf eine
  /// Zuweisung durch den Admin (sofern ein Team frei ist).
  Future<List<FantasyManager>> pendingMembers(String leagueId) async {
    final rows = await _client
        .from('fantasy_league_members')
        .select('user_id, team_name, draft_position, waiver_priority, vacant, pending, profiles(username, avatar_url, avatar_emoji, avatar_color)')
        .eq('league_id', leagueId)
        .eq('pending', true)
        .order('joined_at');
    return rows.map(FantasyManager.fromJson).toList();
  }

  /// Setzt den eigenen ligaspezifischen Teamnamen (leer = löschen). Nur der
  /// eigene Eintrag wird geändert (RPC, security definer).
  Future<void> setTeamName(String leagueId, String name) =>
      _client.rpc('fantasy_set_team_name',
          params: {'p_league_id': leagueId, 'p_name': name});

  Future<void> kickMember(String leagueId, String userId) =>
      _client.rpc('fantasy_kick_member',
          params: {'p_league_id': leagueId, 'p_user': userId});

  /// Übergibt die Adminrechte an ein aktives Mitglied (nur der Admin).
  Future<void> transferOwnership(String leagueId, String newOwnerId) =>
      _client.rpc('fantasy_transfer_ownership',
          params: {'p_league_id': leagueId, 'p_new_owner': newOwnerId});

  /// Übergibt die Adminrechte an ein Mitglied und verlässt danach die Liga
  /// (atomar, nur der Admin).
  Future<void> transferAndLeaveLeague(String leagueId, String newOwnerId) =>
      _client.rpc('fantasy_transfer_and_leave',
          params: {'p_league_id': leagueId, 'p_new_owner': newOwnerId});

  Future<void> assignTeam(
          String leagueId, String vacantUser, String newUser) =>
      _client.rpc('fantasy_assign_team', params: {
        'p_league_id': leagueId,
        'p_vacant_user': vacantUser,
        'p_new_user': newUser,
      });

  Future<void> adminDrop(String leagueId, String target, String playerId) =>
      _client.rpc('fantasy_admin_drop', params: {
        'p_league_id': leagueId,
        'p_target': target,
        'p_player_id': playerId,
      });

  Future<void> adminAdd(String leagueId, String target, String playerId) =>
      _client.rpc('fantasy_admin_add', params: {
        'p_league_id': leagueId,
        'p_target': target,
        'p_player_id': playerId,
      });

  /// Nutzer per Benutzername suchen (für die Team-Zuweisung durch den Admin).
  Future<List<({String id, String username})>> searchProfiles(
      String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final me = _client.auth.currentUser?.id;
    var builder =
        _client.from('profiles').select('id, username').ilike('username', '%$q%');
    if (me != null) builder = builder.neq('id', me);
    final rows = await builder.order('username').limit(20);
    return [
      for (final r in rows)
        (id: r['id'] as String, username: r['username'] as String)
    ];
  }

  /// Aktuelle Kader der Liga in Echtzeit (Draft + Free Agency).
  Stream<List<RosterEntry>> rosterStream(String leagueId) => _client
      .from('fantasy_rosters')
      .stream(primaryKey: ['league_id', 'player_id'])
      .eq('league_id', leagueId)
      .map((rows) => rows.map(RosterEntry.fromJson).toList());

  /// Live-Stream des ligainternen Chats (älteste zuerst, neue unten).
  Stream<List<ChatMessage>> messageStream(String leagueId) => _client
      .from('fantasy_league_messages')
      .stream(primaryKey: ['id'])
      .eq('league_id', leagueId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(ChatMessage.fromJson).toList());

  Future<void> sendMessage(String leagueId, String body,
      {String? replyTo}) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('fantasy_league_messages').insert({
      'league_id': leagueId,
      'user_id': userId,
      'body': body.trim(),
      'reply_to': ?replyTo,
    });
  }

  Future<void> dropPlayer(String leagueId, String playerId) => _client.rpc(
        'fantasy_drop_player',
        params: {'p_league_id': leagueId, 'p_player_id': playerId},
      );

  Future<void> addFreeAgent(String leagueId, String addPlayerId,
          {String? dropPlayerId}) =>
      _client.rpc('fantasy_add_free_agent', params: {
        'p_league_id': leagueId,
        'p_add_player_id': addPlayerId,
        'p_drop_player_id': dropPlayerId,
      });

  // ----------------------------------------------------------------
  // Waiver-Wire
  // ----------------------------------------------------------------

  /// Spieler-IDs, die aktuell auf dem Waiver-Wire liegen (claim-only).
  Stream<Set<String>> waiverPlayersStream(String leagueId) => _client
      .from('fantasy_waiver_players')
      .stream(primaryKey: ['league_id', 'player_id'])
      .eq('league_id', leagueId)
      .map((rows) => {
            for (final r in rows)
              if (DateTime.parse(r['clears_at'] as String).isAfter(DateTime.now()))
                r['player_id'] as String
          });

  /// Eigene Waiver-Anträge der Liga in Echtzeit (RLS: nur die eigenen).
  /// Nach `id` dedupliziert — der Realtime-Stream kann denselben Antrag sonst
  /// doppelt liefern (Initial-Snapshot + Insert-Event), was zu doppelten
  /// Kacheln und einem Fehler beim zweiten Stornieren führte.
  Stream<List<WaiverClaim>> myWaiverClaimsStream(String leagueId) => _client
      .from('fantasy_waiver_claims')
      .stream(primaryKey: ['id'])
      .eq('league_id', leagueId)
      .order('created_at')
      .map((rows) =>
          dedupWaiverClaimsById(rows.map(WaiverClaim.fromJson).toList()));

  /// Nächste Runde + Waiver-Deadline (2 Tage vor Anstoß). Beide null, wenn
  /// kein Spieltag mehr ansteht.
  Future<({int? round, DateTime? deadline})> waiverWindow(int season) async {
    final res = await _client.rpc(
      'fantasy_next_waiver_window',
      params: {'p_season': season},
    );
    // PostgREST liefert je nach Version ein Objekt oder ein 1-Element-Array.
    final row = res is List
        ? (res.isEmpty ? null : res.first as Map<String, dynamic>)
        : res as Map<String, dynamic>?;
    if (row == null) return (round: null, deadline: null);
    final deadline = row['deadline'];
    return (
      round: row['round'] as int?,
      deadline: deadline == null ? null : DateTime.parse(deadline as String),
    );
  }

  Future<void> submitWaiverClaim(String leagueId, String addPlayerId,
          {String? dropPlayerId, int rank = 1}) =>
      _client.rpc('fantasy_submit_waiver_claim', params: {
        'p_league_id': leagueId,
        'p_add_player_id': addPlayerId,
        'p_drop_player_id': dropPlayerId,
        'p_rank': rank,
      });

  Future<void> cancelWaiverClaim(String claimId) => _client.rpc(
        'fantasy_cancel_waiver_claim',
        params: {'p_claim_id': claimId},
      );

  // ----------------------------------------------------------------
  // Manuelle Aufstellung
  // ----------------------------------------------------------------

  /// Alle Aufstellungen der Liga in Echtzeit (für „Mein Team" & Tabelle);
  /// nach Spieltag wird im Client gefiltert.
  Stream<List<FantasyLineup>> lineupsStream(String leagueId) => _client
      .from('fantasy_lineups')
      .stream(primaryKey: ['league_id', 'manager_id', 'season', 'round'])
      .eq('league_id', leagueId)
      .map((rows) => rows.map(FantasyLineup.fromJson).toList());

  /// Aufstellungs-Deadline (erster Anstoß des Spieltags); null, wenn der
  /// Spieltag (noch) nicht in den gespiegelten Fixtures liegt.
  Future<DateTime?> roundDeadline(int season, int round) async {
    final ts = await _client.rpc<String?>('fantasy_round_deadline',
        params: {'p_season': season, 'p_round': round});
    return ts == null ? null : DateTime.parse(ts);
  }

  Future<void> setLineup(String leagueId, int round, List<String> playerIds) =>
      _client.rpc('fantasy_set_lineup', params: {
        'p_league_id': leagueId,
        'p_round': round,
        'p_player_ids': playerIds,
      });
}
