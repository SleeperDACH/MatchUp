import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/data/openligadb/openligadb_provider.dart';
import '../../core/logic/round_robin.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/models.dart';
import '../auth/providers.dart';
import '../tippspiel/providers.dart' show chatLastReadProvider;
import 'data/db_fantasy_data_provider.dart';
import 'data/draft_repository.dart';
import 'data/fantasy_data_provider.dart';
import 'data/fantasy_league_repository.dart';
import 'data/fantasy_stats_source.dart';
import 'data/round_scoring_service.dart';
import 'data/seed_player_pool.dart';
import 'logic/draft_ranking.dart';
import 'logic/fantasy_scoring_engine.dart';
import 'models/fantasy_models.dart';
import 'models/trade.dart';

final fantasyLeagueRepositoryProvider = Provider<FantasyLeagueRepository>(
    (ref) => FantasyLeagueRepository(Supabase.instance.client));

final draftRepositoryProvider =
    Provider<DraftRepository>((ref) => DraftRepository(Supabase.instance.client));

/// Datenquelle für Spielerpool und (später) Live-Punkte. Mit Server der
/// DB-Pool; ohne Konfiguration der Offline-Seed.
final fantasyDataProvider = Provider<FantasyDataProvider>((ref) =>
    AppConfig.isSupabaseConfigured
        ? DbFantasyDataProvider(Supabase.instance.client)
        : const SeedFantasyDataProvider());

/// Startjahr der aktuellen Fantasy-Saison (Bundesliga-Rhythmus).
final fantasySeasonProvider =
    Provider<int>((ref) => Leagues.bundesliga.seasonFor(DateTime.now()));

/// Die eigenen Fantasy-Ligen — **live**.
///
/// War ein `FutureProvider` und lud damit genau einmal. Ein gestarteter Draft
/// oder eine neu beigetretene Liga erschien erst nach einem vollständigen
/// App-Neustart; gemeldet wurde das als Performance-Problem.
final myFantasyLeaguesProvider = StreamProvider<List<FantasyLeague>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const <FantasyLeague>[]);
  return ref.watch(fantasyLeagueRepositoryProvider).myLeaguesStream();
});

/// Die Mitglieder einer Liga — **live**.
///
/// Ebenfalls vorher ein `FutureProvider`. Der Draft-Raum hat das mit einem
/// `ref.invalidate` alle zwei Sekunden überdeckt — eine Notlösung, die die
/// Liste nur *dort* aktuell hielt und dafür im Sekundentakt abfragte. Die ist
/// mit dieser Umstellung entfallen.
///
/// `asyncMap` statt `map`: Der Stream ist nur die Klingel (siehe
/// [FantasyLeagueRepository.memberChanges]), die Liste mit Namen und Avataren
/// kommt aus der vollständigen Abfrage.
final fantasyManagersProvider =
    StreamProvider.family<List<FantasyManager>, String>((ref, leagueId) {
  final repo = ref.watch(fantasyLeagueRepositoryProvider);
  return repo.memberChanges(leagueId).asyncMap((_) => repo.managers(leagueId));
});

/// Verwaiste Teams einer Liga (für die Admin-Zuweisung).
final vacantTeamsProvider =
    FutureProvider.family<List<FantasyManager>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).vacantTeams(leagueId);
});

/// Nach Draft-Start beigetretene Mitglieder ohne Team (warten auf Zuweisung).
final pendingMembersProvider =
    FutureProvider.family<List<FantasyManager>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).pendingMembers(leagueId);
});

/// Aktuelle Kader der Liga in Echtzeit (Draft + Free Agency).
final leagueRosterProvider =
    StreamProvider.family<List<RosterEntry>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).rosterStream(leagueId);
});

/// Live-Stream der Chat-Nachrichten einer Fantasy-Liga (älteste zuerst).
final fantasyMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).messageStream(leagueId);
});

/// Ungelesene Nachrichten im Liga-Chat? Lokale „gelesen bis"-Marke pro Gerät
/// (teilt sich den generischen Marker mit dem Tippspiel-Chat; Schlüssel =
/// league_id, kollidiert nicht mit den Runden-IDs).
final fantasyUnreadChatProvider = Provider.family<bool, String>((ref, leagueId) {
  final myId = ref.watch(currentUserProvider)?.id;
  final lastRead = ref.watch(chatLastReadProvider(leagueId));
  final messages =
      ref.watch(fantasyMessagesProvider(leagueId)).valueOrNull ?? const [];
  return messages.any((m) =>
      m.userId != myId && (lastRead == null || m.createdAt.isAfter(lastRead)));
});

/// Die eigene Formation für den aktuellen Spieltag — `null`, wenn keine
/// Aufstellung gespeichert ist.
///
/// Damit die Zeile „Aufstellung" auf der Liga-Übersicht **etwas sagen kann**.
/// Sie trug vorher nur ihr Wort, und damit war die wöchentlich wichtigste
/// Aufgabe der Liga von „Liga-Chat" nicht zu unterscheiden.
final meineFormationProvider =
    Provider.family<String?, String>((ref, leagueId) {
  final myId = ref.watch(currentUserProvider)?.id;
  final runde = ref.watch(fantasyCurrentRoundProvider).valueOrNull;
  if (myId == null || runde == null) return null;
  final ids = (ref.watch(leagueLineupsProvider(leagueId)).valueOrNull ??
          const <FantasyLineup>[])
      .where((l) => l.managerId == myId && l.round == runde)
      .map((l) => l.playerIds)
      .firstOrNull;
  if (ids == null || ids.isEmpty) return null;
  final pool = ref.watch(playerPoolProvider).valueOrNull;
  if (pool == null) return null;
  final byId = {for (final p in pool) p.id: p};
  var d = 0, m = 0, f = 0;
  for (final id in ids) {
    switch (byId[id]?.position) {
      case PlayerPosition.def:
        d++;
      case PlayerPosition.mid:
        m++;
      case PlayerPosition.fwd:
        f++;
      default:
        break;
    }
  }
  return '$d-$m-$f';
});

/// Trade-Angebote einer Liga (RLS: nur eigene Beteiligung) in Echtzeit.
final leagueTradesProvider =
    StreamProvider.family<List<TradeOffer>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).tradesStream(leagueId);
});

/// Anzahl offener Trade-Angebote, die an mich gerichtet sind (eingehend,
/// noch nicht beantwortet) — für den auffälligen Hinweis am Trade-Button.
final incomingTradeOffersProvider =
    Provider.family<int, String>((ref, leagueId) {
  final myId = ref.watch(currentUserProvider)?.id;
  if (myId == null) return 0;
  final trades =
      ref.watch(leagueTradesProvider(leagueId)).valueOrNull ?? const [];
  return trades
      .where((t) => t.toManager == myId && t.status.isPending)
      .length;
});

/// Meine **vorgemerkten** Trades: angenommen, aber die Spieler haben den Kader
/// noch nicht gewechselt.
///
/// Seit Migration 0088 greift ein Tausch erst 12 Stunden nach dem letzten
/// Spiel der Runde — sonst nähme er einem Manager mitten in der Wertung einen
/// Spieler aus der Elf. Dazwischen liegt ein Zustand, den es vorher nicht gab
/// und den der Kader-Tab zeigen muss: „abgemacht, aber noch nicht vollzogen".
final vorgemerkteTradesProvider =
    Provider.family<List<TradeOffer>, String>((ref, leagueId) {
  final myId = ref.watch(currentUserProvider)?.id;
  if (myId == null) return const [];
  final trades =
      ref.watch(leagueTradesProvider(leagueId)).valueOrNull ?? const [];
  return [
    for (final t in trades)
      if (t.wartetAufAusfuehrung &&
          (t.fromManager == myId || t.toManager == myId))
        t
  ]..sort((a, b) => (a.executeAfter ?? a.createdAt)
      .compareTo(b.executeAfter ?? b.createdAt));
});

/// Einzelnes Trade-Angebot samt Positionen (für die Chat-Karte).
final tradeDetailProvider = FutureProvider.family<
    ({TradeOffer trade, List<TradeItem> items})?, String>((ref, tradeId) {
  return ref.watch(fantasyLeagueRepositoryProvider).tradeById(tradeId);
});

/// Positionen aller eigenen Trades, gruppiert nach `trade_id` (Echtzeit).
final tradeItemsProvider =
    StreamProvider<Map<String, List<TradeItem>>>((ref) {
  return ref
      .watch(fantasyLeagueRepositoryProvider)
      .tradeItemsStream()
      .map((items) {
    final byTrade = <String, List<TradeItem>>{};
    for (final it in items) {
      byTrade.putIfAbsent(it.tradeId, () => []).add(it);
    }
    return byTrade;
  });
});

/// Spieler-IDs auf dem Waiver-Wire (nach Drop claim-only) in Echtzeit.
final waiverPlayersProvider =
    StreamProvider.family<Set<String>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).waiverPlayersStream(leagueId);
});

/// Eigene Waiver-Anträge der Liga in Echtzeit.
final myWaiverClaimsProvider =
    StreamProvider.family<List<WaiverClaim>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).myWaiverClaimsStream(leagueId);
});

/// Nächste Runde + Waiver-Deadline (2 Tage vor Anstoß) der Saison.
final waiverWindowProvider =
    FutureProvider<({int? round, DateTime? deadline})>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyLeagueRepositoryProvider).waiverWindow(season);
});

/// Alle manuellen Aufstellungen einer Liga in Echtzeit (alle Spieltage).
final leagueLineupsProvider =
    StreamProvider.family<List<FantasyLineup>, String>((ref, leagueId) {
  return ref.watch(fantasyLeagueRepositoryProvider).lineupsStream(leagueId);
});

/// Aufstellungs-Deadline (erster Anstoß) eines Spieltags der Saison.
final roundDeadlineProvider =
    FutureProvider.family<DateTime?, int>((ref, round) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyLeagueRepositoryProvider).roundDeadline(season, round);
});

final playerPoolProvider = FutureProvider<List<FantasyPlayer>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyDataProvider).getPlayerPool(season: season);
});

/// Vereinslogos (kanonischer Name → Icon-URL) aus der Bundesliga-Tabelle,
/// um bei Spielern das Vereinswappen zu zeigen. Fällt auf die Vorsaison
/// zurück, falls die aktuelle Tabelle noch leer ist (Saisonstart).
final clubIconsProvider = FutureProvider<Map<String, String?>>((ref) async {
  final season = ref.watch(fantasySeasonProvider);
  final provider = OpenLigaDbProvider();
  var rows = await provider.getTable(Leagues.bundesliga, season);
  if (rows.isEmpty) {
    rows = await provider.getTable(Leagues.bundesliga, season - 1);
  }
  return {for (final r in rows) r.team.name: r.team.iconUrl};
});

// ------------------------------------------------------------------
// Draft (Realtime)
// ------------------------------------------------------------------

/// Liga-Zustand in Echtzeit (Draft-Status, Picks, Deadline).
final draftLeagueProvider =
    StreamProvider.family<FantasyLeague?, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).leagueStream(leagueId);
});

/// Alle Picks der Liga in Echtzeit.
final draftPicksProvider =
    StreamProvider.family<List<DraftPick>, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).picksStream(leagueId);
});

/// Eigene Draft-Queue (Spieler-IDs nach Rang) in Echtzeit.
final draftQueueProvider =
    StreamProvider.family<List<String>, String>((ref, leagueId) {
  return ref.watch(draftRepositoryProvider).queueStream(leagueId);
});

// ------------------------------------------------------------------
// Scoring (Stats-Feed: serverseitig gespiegelt, Fallback live OpenLigaDB)
// ------------------------------------------------------------------

final roundScoringServiceProvider =
    Provider<RoundScoringService>((ref) => RoundScoringService());

/// Quelle der Roh-Stats: mit Supabase die Tabelle player_match_stats
/// (Quelle der Wahrheit, Schema bereit für Assists/Karten/Minuten), sonst
/// bzw. als Fallback die Live-Berechnung aus OpenLigaDB.
final fantasyStatsSourceProvider = Provider<FantasyStatsSource>((ref) {
  final live = LiveStatsSource(ref.watch(roundScoringServiceProvider));
  return AppConfig.isSupabaseConfigured
      ? DbStatsSource(Supabase.instance.client, live)
      : live;
});

/// Roh-Aggregate der letzten Saison je Spieler (aus player_season_totals) —
/// Basis für die Draft-Reihung „bester zuerst". Leer im lokalen Modus.
final lastSeasonTotalsProvider =
    FutureProvider<Map<String, SeasonTotals>>((ref) async {
  if (!AppConfig.isSupabaseConfigured) return const {};
  final lastSeason = ref.watch(fantasySeasonProvider) - 1;
  final rows = await Supabase.instance.client
      .from('player_season_totals')
      .select()
      .eq('season', lastSeason);
  return {
    for (final r in rows)
      r['player_id'] as String: SeasonTotals.fromJson(r),
  };
});

/// Aktueller bzw. letzter Bundesliga-Spieltag (Standard für die Anzeige).
/// Alle Bundesliga-Fixtures der Fantasy-Saison (Anstoßzeiten, Teams,
/// Ergebnisse) — Basis für die Spieltags-Anzeige und den aktuellen Spieltag.
final fantasySeasonFixturesProvider = FutureProvider<List<Fixture>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return OpenLigaDbProvider().getSeasonFixtures(Leagues.bundesliga, season);
});

/// Aktueller Fantasy-Spieltag: der erste Spieltag, dessen **letzter Anpfiff**
/// noch keine 24 h zurückliegt. Ein beendeter Spieltag bleibt also 24 h nach
/// dem letzten Anpfiff stehen und springt danach auf den nächsten.
final fantasyCurrentRoundProvider = FutureProvider<int>((ref) async {
  final fixtures = await ref.watch(fantasySeasonFixturesProvider.future);
  return currentFantasyRound(fixtures, DateTime.now());
});

/// Pure Regel für [fantasyCurrentRoundProvider] (24 h nach letztem Anpfiff).
int currentFantasyRound(List<Fixture> fixtures, DateTime now) {
  if (fixtures.isEmpty) return 1;
  final lastKick = <int, DateTime>{};
  for (final f in fixtures) {
    final cur = lastKick[f.round];
    if (cur == null || f.kickoff.isAfter(cur)) lastKick[f.round] = f.kickoff;
  }
  final rounds = lastKick.keys.toList()..sort();
  for (final r in rounds) {
    if (now.isBefore(lastKick[r]!.add(const Duration(hours: 24)))) return r;
  }
  return rounds.last; // Saison vorbei → letzter Spieltag.
}

/// Läuft der Spieltag gerade? „Live" ist das Fenster vom **ersten Anpfiff**
/// bis zum **letzten Abpfiff**: sobald der früheste Anstoß der Runde vorbei
/// ist und noch nicht alle Partien beendet sind (inkl. der Pausen zwischen
/// den Spielen an verschiedenen Tagen). Vor dem ersten Anstoß und nach dem
/// letzten Abpfiff ist die Runde nicht live.
bool roundIsLive(List<Fixture> roundFixtures, DateTime now) {
  if (roundFixtures.isEmpty) return false;
  final firstKick = roundFixtures
      .map((f) => f.kickoff)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  if (now.isBefore(firstKick)) return false;
  final allFinished =
      roundFixtures.every((f) => f.status == FixtureStatus.finished);
  return !allFinished;
}

/// Takt, in dem die Punkte eines laufenden Spieltags nachgeladen werden.
///
/// Serverseitig holt `sync-stats` im Minutentakt (Migration 0080); häufiger
/// nachzufragen brächte nichts als Last. Etwas darunter zu bleiben sorgt
/// dafür, dass ein neuer Serverstand im Schnitt nach einer halben Minute auf
/// dem Schirm steht.
const _liveStatsTakt = Duration(seconds: 30);

/// Läuft dieser Spieltag gerade? (Erster Anpfiff bis letzter Abpfiff.)
final roundIsLiveProvider = Provider.family<bool, int>((ref, round) {
  final fixtures = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
  if (fixtures == null) return false;
  return roundIsLive(
    fixtures.where((f) => f.round == round).toList(),
    DateTime.now(),
  );
});

/// Ist der Spieltag **abgepfiffen** — also jede Partie beendet?
///
/// Anders als [roundIsLiveProvider]: „nicht live" heißt auch vor dem ersten
/// Anpfiff, „abgepfiffen" nur danach. Der Wochen-Recap hängt daran — er ist
/// eine Bilanz, und eine Bilanz über einen halb gespielten Spieltag ist keine.
final rundeAbgepfiffenProvider = Provider.family<bool, int>((ref, round) {
  final fixtures = ref.watch(fantasySeasonFixturesProvider).valueOrNull;
  if (fixtures == null) return false;
  final spiele = [
    for (final f in fixtures)
      if (f.round == round) f
  ];
  return spiele.isNotEmpty &&
      spiele.every((f) => f.status == FixtureStatus.finished);
});

/// Alle **abgepfiffenen** Spieltage der Saison, aufsteigend — die Spieltage,
/// für die es einen Recap zum Nachschlagen gibt.
final abgepfiffeneRundenProvider = Provider<List<int>>((ref) {
  final fixtures =
      ref.watch(fantasySeasonFixturesProvider).valueOrNull ?? const <Fixture>[];
  final proRunde = <int, List<Fixture>>{};
  for (final f in fixtures) {
    (proRunde[f.round] ??= []).add(f);
  }
  final fertig = [
    for (final e in proRunde.entries)
      if (e.value.every((f) => f.status == FixtureStatus.finished)) e.key
  ]..sort();
  return fertig;
});

/// Roh-Leistungsdaten aller Poolspieler für einen Spieltag.
///
/// **Lädt nach, solange der Spieltag läuft.** Vorher war das ein einfacher
/// `FutureProvider`: einmal geladen, nie wieder — die Punkte standen also auf
/// dem Stand, den der Schirm beim Öffnen vorfand, und bewegten sich während
/// des Spiels nicht. Für „Live-Punkte" reicht es nicht, dass der Server sie
/// schreibt; der Client muss auch hinsehen.
///
/// Ein einmaliger `Timer` statt `Timer.periodic`: Nach dem Neuladen baut sich
/// der Provider ohnehin neu auf und stellt den nächsten. Läuft nichts, wird
/// kein Timer gestellt — außerhalb der Spielfenster fragt die App also nicht.
final roundStatsProvider =
    FutureProvider.family<Map<String, PlayerMatchStats>, int>((ref, round) async {
  final pool = await ref.watch(playerPoolProvider.future);
  final season = ref.watch(fantasySeasonProvider);
  final stats = await ref
      .watch(fantasyStatsSourceProvider)
      .roundStats(pool: pool, season: season, round: round);

  if (ref.watch(roundIsLiveProvider(round))) {
    final timer = Timer(_liveStatsTakt, () {
      // Die Spielpläne mit auffrischen: Ohne sie bliebe der Spieltag nach dem
      // Abpfiff für immer „live", und die App fragte bis zum Neustart weiter.
      ref.invalidate(fantasySeasonFixturesProvider);
      ref.invalidateSelf();
    });
    ref.onDispose(timer.cancel);
  }
  return stats;
});

/// Alle gespielten Spieltage der Saison (Spieltag → Spieler-ID → Stats);
/// Grundlage der Head-to-Head-Bilanz. Leer ohne serverseitige Stats.
final seasonStatsProvider =
    FutureProvider<Map<int, Map<String, PlayerMatchStats>>>((ref) {
  final season = ref.watch(fantasySeasonProvider);
  return ref.watch(fantasyStatsSourceProvider).seasonStats(season: season);
});

/// Mein H2H-Tabellenplatz in einer Liga — `null`, solange nichts feststeht:
/// Draft nicht fertig, weniger als zwei Manager, Daten noch nicht geladen
/// oder noch kein Spieltag gewertet.
///
/// Die Rechnung lag früher im `FantasyRankChip`-Widget. Für die Liga-Karte
/// auf dem Homescreen wird sie aber als **Wert** gebraucht (steht ein Platz
/// fest, verdrängt er den Zustandstext) — und ein Widget kann man nicht
/// fragen, ob es etwas gezeichnet hat. Der Chip liest jetzt hier mit, damit
/// es die Wertung nicht zweimal gibt.
final myFantasyRankProvider =
    Provider.family<({int rank, int total})?, String>((ref, leagueId) {
  final league = ref
      .watch(myFantasyLeaguesProvider)
      .valueOrNull
      ?.where((l) => l.id == leagueId)
      .firstOrNull;
  if (league == null || league.draftStatus != DraftStatus.done) return null;

  final myId = ref.watch(currentUserProvider)?.id;
  final managers = ref.watch(fantasyManagersProvider(leagueId)).valueOrNull;
  final pool = ref.watch(playerPoolProvider).valueOrNull;
  final roster = ref.watch(leagueRosterProvider(leagueId)).valueOrNull;
  final seasonStats = ref.watch(seasonStatsProvider).valueOrNull;
  final lineups = ref.watch(leagueLineupsProvider(leagueId)).valueOrNull;

  if (myId == null ||
      managers == null ||
      managers.length < 2 ||
      pool == null ||
      roster == null ||
      seasonStats == null) {
    return null;
  }

  final playerById = {for (final p in pool) p.id: p};
  final ids = managers.map((m) => m.userId).toList()
    ..sort((a, b) {
      final pa =
          managers.firstWhere((m) => m.userId == a).draftPosition ?? 1 << 30;
      final pb =
          managers.firstWhere((m) => m.userId == b).draftPosition ?? 1 << 30;
      return pa != pb ? pa.compareTo(pb) : a.compareTo(b);
    });

  final totalsByRound = <int, Map<String, double>>{
    for (final entry in seasonStats.entries)
      entry.key: effectiveTotalsForRound(
        stats: entry.value,
        round: entry.key,
        managers: managers,
        roster: roster,
        playerById: playerById,
        lineups: lineups ?? const <FantasyLineup>[],
        scoring: league.scoring,
        rosterConfig: league.roster,
      )
  };
  final standings = h2hStandings(ids, totalsByRound);
  // Vor dem ersten gewerteten Spieltag stehen alle auf null — das ist kein
  // Tabellenplatz, sondern eine Reihenfolge nach Zufall.
  if (standings.every((r) => r.played == 0)) return null;

  final idx = standings.indexWhere((r) => r.managerId == myId);
  if (idx < 0) return null;
  return (rank: idx + 1, total: managers.length);
});
