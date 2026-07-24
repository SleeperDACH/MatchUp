import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/data/odds/frozen_odds.dart';
import '../../core/data/odds/match_odds.dart';
import '../../core/data/odds/odds_matching.dart';
import '../../core/data/odds/odds_provider.dart';
import '../../core/data/openligadb/openligadb_provider.dart';
import '../../core/data/sports_data_provider.dart';
import '../../core/data/sportmonks/sportmonks_provider.dart';
import '../../core/models/match_detail.dart';
import '../../core/models/models.dart';
import '../../core/models/top_scorer.dart';
import '../auth/providers.dart';
import 'data/tip_round_repository.dart';
import 'data/tip_store.dart';
import 'logic/tip_stats.dart';
import 'logic/tip_weeks.dart';
import 'models/chat_message.dart';
import 'models/tip.dart';
import 'models/tip_round.dart';

/// Aktiver Wettbewerb; umschaltbar über den Titel der App-Bar.
final selectedLeagueProvider =
    StateProvider<LeagueInfo>((ref) => Leagues.bundesliga);

/// Saison-Startjahr des aktiven Wettbewerbs (Turniere: festes Jahr,
/// Vereinsligen: Saisonwechsel im Juli).
final seasonProvider = Provider<int>((ref) {
  return ref.watch(selectedLeagueProvider).seasonFor(DateTime.now());
});

final sportsDataProvider = Provider<SportsDataProvider>((ref) {
  final league = ref.watch(selectedLeagueProvider);
  // Tipp-Flow läuft jetzt über denselben Adapter wie Live/Übersicht: die 5
  // deutschen Ligen über Sportmonks (`sportmonks:`-IDs), WM über OpenLigaDB.
  // `sync-fixtures` spiegelt dieselben IDs serverseitig, damit die
  // Deadline-RLS beim Tipp-Speichern die Fixture findet.
  return sportsProviderFor(league);
});

final currentRoundProvider = FutureProvider<int>((ref) {
  final league = ref.watch(selectedLeagueProvider);
  final season = ref.watch(seasonProvider);
  return ref.watch(sportsDataProvider).getCurrentRound(league, season);
});

/// Alle Runden des aktiven Wettbewerbs (inkl. noch nicht ausgeloster
/// K.o.-Runden bei Turnieren) mit offiziellen Namen.
final availableRoundsProvider = FutureProvider<List<RoundInfo>>((ref) {
  final league = ref.watch(selectedLeagueProvider);
  final season = ref.watch(seasonProvider);
  return ref.watch(sportsDataProvider).getRounds(league, season);
});

/// Vom Nutzer gewählte Runde; `null` = aktuelle Runde. Setzt sich beim
/// Wettbewerbswechsel automatisch zurück.
final selectedRoundProvider = StateProvider<int?>((ref) {
  ref.watch(selectedLeagueProvider);
  return null;
});

final roundFixturesProvider =
    FutureProvider.family<List<Fixture>, int>((ref, round) {
  final league = ref.watch(selectedLeagueProvider);
  final season = ref.watch(seasonProvider);
  return ref.watch(sportsDataProvider).getRoundFixtures(league, season, round);
});

final seasonFixturesProvider = FutureProvider<List<Fixture>>((ref) {
  final league = ref.watch(selectedLeagueProvider);
  final season = ref.watch(seasonProvider);
  return ref.watch(sportsDataProvider).getSeasonFixtures(league, season);
});

/// Saison-Fixtures einer beliebigen Liga (per ID) — für ligenübergreifende
/// Ansichten wie den Live-Tab, unabhängig vom aktuell gewählten Wettbewerb.
/// Detaildaten eines einzelnen Spiels (Ergebnis, Torschützen, Spielort) —
/// für die Spiel-Detailansicht. Family-Key ist die Fixture-ID
/// (z. B. `openligadb:80140`).
final matchDetailProvider =
    FutureProvider.family<MatchDetail, String>((ref, fixtureId) {
  // Provider aus dem ID-Präfix ableiten (`sportmonks:…` / `openligadb:…`).
  if (fixtureId.startsWith('sportmonks:')) {
    if (!AppConfig.isSupabaseConfigured) {
      throw StateError('Sportmonks-Daten brauchen die Server-Verbindung.');
    }
    return SupabaseSportmonksProvider().getMatchDetail(fixtureId);
  }
  final id = int.tryParse(fixtureId.split(':').last);
  if (id == null) {
    throw ArgumentError('Ungültige Fixture-ID: $fixtureId');
  }
  return OpenLigaDbProvider().getMatchDetail(id);
});

/// Baut den passenden Daten-Adapter für eine Liga. Sportmonks läuft über die
/// Edge Function (Key serverseitig) und braucht daher die Server-Verbindung.
SportsDataProvider sportsProviderFor(LeagueInfo league) =>
    switch (league.providerId) {
      'openligadb' => OpenLigaDbProvider(),
      'sportmonks' => AppConfig.isSupabaseConfigured
          ? SupabaseSportmonksProvider()
          : throw StateError(
              'Sportmonks-Daten brauchen die Server-Verbindung.'),
      _ => throw StateError('Unbekannter Datenprovider: ${league.providerId}'),
    };

final leagueSeasonFixturesProvider =
    FutureProvider.family<List<Fixture>, String>((ref, leagueId) {
  final league = Leagues.byId(leagueId);
  final season = league.seasonFor(DateTime.now());
  return sportsProviderFor(league).getSeasonFixtures(league, season);
});

/// Tabelle einer beliebigen Liga (per ID) — für die Liga-Übersicht.
final leagueTableProvider =
    FutureProvider.family<List<StandingRow>, String>((ref, leagueId) {
  final league = Leagues.byId(leagueId);
  final season = league.seasonFor(DateTime.now());
  return sportsProviderFor(league).getTable(league, season);
});

/// Torjägerliste einer Liga (nur Sportmonks-Ligen; braucht Server-Verbindung).
final leagueTopScorersProvider =
    FutureProvider.family<TopScorersResult, String>((ref, leagueId) {
  final league = Leagues.byId(leagueId);
  if (league.sportmonksKey == null || !AppConfig.isSupabaseConfigured) {
    return const TopScorersResult(current: true, scorers: []);
  }
  return SupabaseSportmonksProvider().getTopScorers(league);
});

// ---------------------------------------------------------------------
// Wettquoten (the-odds-api.com) — nur Anzeige
// ---------------------------------------------------------------------

/// Mit Backend läuft der Abruf über die Edge Function (Key bleibt geheim);
/// nur im lokalen Modus ohne Supabase wird direkt mit dart-define-Key geholt.
final oddsProviderProvider = Provider<OddsProvider>((ref) {
  return AppConfig.isSupabaseConfigured
      ? SupabaseOddsProvider()
      : TheOddsApiProvider();
});

/// Aktuelle Quoten des gewählten Wettbewerbs. Wird pro Liga einmal geholt
/// und für die Session gecacht (die Edge Function cached zusätzlich
/// serverseitig). Leere Liste, wenn die Liga keine Quoten-Quelle hat oder
/// keine Quelle verfügbar ist.
final leagueOddsProvider = FutureProvider<List<MatchOdds>>((ref) async {
  final sportKey = ref.watch(selectedLeagueProvider).oddsSportKey;
  final available = AppConfig.isSupabaseConfigured || AppConfig.hasOdds;
  if (sportKey == null || !available) return const [];
  return ref.watch(oddsProviderProvider).fetchOdds(sportKey);
});

/// Quoten einer Runde, fertig auf Fixture-IDs gematcht. Leeres Map, solange
/// Quoten/Spiele noch laden oder nichts passt — die UI bleibt dann ohne.
final roundOddsProvider =
    Provider.family<Map<String, MatchOdds>, int>((ref, round) {
  final sportKey = ref.watch(selectedLeagueProvider).oddsSportKey;
  if (sportKey == null) return const {};
  final odds = ref.watch(leagueOddsProvider).valueOrNull;
  final fixtures = ref.watch(roundFixturesProvider(round)).valueOrNull;
  if (odds == null || odds.isEmpty || fixtures == null) return const {};
  return matchOdds(sportKey, fixtures, odds);
});

/// Quoten einer beliebigen Liga (per ID) — wie [leagueOddsProvider], aber nicht
/// an den aktuell gewählten Wettbewerb gebunden. Für den Wochen-Feed, der
/// Spiele mehrerer Wettbewerbe gemischt zeigt.
final leagueOddsByIdProvider =
    FutureProvider.family<List<MatchOdds>, String>((ref, leagueId) async {
  final sportKey = Leagues.byId(leagueId).oddsSportKey;
  final available = AppConfig.isSupabaseConfigured || AppConfig.hasOdds;
  if (sportKey == null || !available) return const [];
  return ref.watch(oddsProviderProvider).fetchOdds(sportKey);
});

// ---------------------------------------------------------------------
// Spielwochen (Do–Mi) für Multi-Wettbewerb-Tipprunden
// ---------------------------------------------------------------------

/// Spielwochen der aktiven Multi-Wettbewerb-Runde: Union der Saison-Fixtures
/// aller Wettbewerbe, in Do–Mi-Wochen gebündelt. Leere Liste bei Einzel-Liga-
/// Runden oder ohne aktive Runde (dort greift der Spieltag-Pfad).
final roundWeeksProvider = FutureProvider<List<TipWeek>>((ref) async {
  final round = ref.watch(activeRoundProvider);
  if (round == null || round.competitions.length < 2) return const <TipWeek>[];
  final all = <Fixture>[];
  for (final id in round.competitions) {
    all.addAll(await ref.watch(leagueSeasonFixturesProvider(id).future));
  }
  return buildWeeks(all);
});

/// Vom Nutzer gewählte Spielwoche (1-basiert); `null` = aktuelle Woche.
/// Setzt sich beim Wechsel der aktiven Runde zurück.
final selectedWeekProvider = StateProvider<int?>((ref) {
  ref.watch(activeRoundProvider);
  return null;
});

/// Auf Fixture-IDs gematchte Quoten aller Spiele einer Spielwoche (über die
/// Wettbewerbe hinweg). Leer, solange etwas lädt oder nichts passt — die
/// Quotenzeile ist optional und blockiert den Feed nicht.
final weekOddsProvider =
    Provider.family<Map<String, MatchOdds>, int>((ref, weekIndex) {
  final round = ref.watch(activeRoundProvider);
  if (round == null) return const {};
  final weeks = ref.watch(roundWeeksProvider).valueOrNull;
  if (weeks == null) return const {};
  TipWeek? week;
  for (final w in weeks) {
    if (w.index == weekIndex) {
      week = w;
      break;
    }
  }
  if (week == null) return const {};

  final result = <String, MatchOdds>{};
  for (final id in round.competitions) {
    final sportKey = Leagues.byId(id).oddsSportKey;
    if (sportKey == null) continue;
    final odds = ref.watch(leagueOddsByIdProvider(id)).valueOrNull;
    if (odds == null || odds.isEmpty) continue;
    final fixtures = week.fixtures.where((f) => f.leagueId == id).toList();
    if (fixtures.isEmpty) continue;
    result.addAll(matchOdds(sportKey, fixtures, odds));
  }
  return result;
});

// ---------------------------------------------------------------------
// Tipprunden (Supabase)
// ---------------------------------------------------------------------

final tipRoundRepositoryProvider = Provider<TipRoundRepository>(
    (ref) => TipRoundRepository(Supabase.instance.client));

/// Zum Anstoß eingefrorene Quoten je Fixture — Grundlage für den
/// Quoten-Bonus in der Wertung. Nur mit Backend; im lokalen Modus leer
/// (dort gibt es keinen serverseitigen Snapshot).
final frozenOddsProvider = FutureProvider<Map<String, FrozenOdds>>((ref) {
  if (!AppConfig.isSupabaseConfigured) {
    return Future.value(const <String, FrozenOdds>{});
  }
  return ref.watch(tipRoundRepositoryProvider).frozenOdds();
});

final myRoundsProvider = FutureProvider<List<TipRound>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(const <TipRound>[]);
  return ref.watch(tipRoundRepositoryProvider).myRounds();
});

/// Eigene Tipp-Bilanz über alle Tipprunden — für das Profil-Dashboard.
final myTipStatsProvider = FutureProvider<TipStats>((ref) async {
  final myId = ref.watch(currentUserProvider)?.id;
  if (myId == null) return TipStats.empty;
  final rounds = await ref.watch(myRoundsProvider.future);
  if (rounds.isEmpty) return TipStats.empty;

  final frozen = await ref.watch(frozenOddsProvider.future);
  final tipsByRound = <String, List<MemberTip>>{};
  final fixturesById = <String, Fixture>{};
  final loadedLeagues = <String>{};
  for (final r in rounds) {
    tipsByRound[r.id] = await ref.watch(allRoundTipsProvider(r.id).future);
    if (loadedLeagues.add(r.leagueId)) {
      final fixtures =
          await ref.watch(leagueSeasonFixturesProvider(r.leagueId).future);
      for (final f in fixtures) {
        fixturesById[f.id] = f;
      }
    }
  }
  return computeTipStats(
    userId: myId,
    rounds: rounds,
    tipsByRound: tipsByRound,
    fixturesById: fixturesById,
    frozenOdds: frozen,
  );
});

/// Die Tipprunde, in der gerade getippt wird; `null` = lokaler Modus.
final activeRoundProvider = StateProvider<TipRound?>((ref) {
  // Bei Logout zurück in den lokalen Modus.
  if (ref.watch(currentUserProvider) == null) return null;
  return null;
});

/// Aktiviert eine Tipprunde und schaltet den Wettbewerb passend um —
/// immer zusammen verwenden, damit Tippen-Tab und Runde zusammenpassen.
void activateRound(WidgetRef ref, TipRound round) {
  // Primärer Wettbewerb der Runde (bei Multi-Wettbewerb der erste); im
  // Tippen-Tab kann zwischen den Wettbewerben der Runde gewechselt werden.
  ref.read(selectedLeagueProvider.notifier).state =
      Leagues.byId(round.competitions.first);
  ref.read(activeRoundProvider.notifier).state = round;
}

/// Mitglieder einer Liga (inkl. Mitglieder ohne Tipps).
final roundMembersProvider =
    FutureProvider.family<List<RoundMember>, String>((ref, roundId) {
  return ref.watch(tipRoundRepositoryProvider).members(roundId);
});

/// Die mit einer Fantasy-Liga gekoppelte Tipprunde (oder null) — Grundlage für
/// den „Ligainternes Tippspiel"-Button auf der Fantasy-Übersicht.
final fantasyTipRoundProvider =
    FutureProvider.family<TipRound?, String>((ref, fantasyLeagueId) {
  return ref.watch(tipRoundRepositoryProvider).fantasyTipRound(fantasyLeagueId);
});

/// Live-Stream der Chat-Nachrichten einer Liga (älteste zuerst).
final roundMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, roundId) {
  return ref.watch(tipRoundRepositoryProvider).messageStream(roundId);
});

/// Zeitpunkt, bis zu dem der Liga-Chat zuletzt gelesen wurde — lokal je
/// Gerät gespeichert (SharedPreferences). `null` = noch nie geöffnet.
final chatLastReadProvider =
    StateNotifierProvider.family<ChatReadNotifier, DateTime?, String>(
        (ref, roundId) => ChatReadNotifier(roundId));

class ChatReadNotifier extends StateNotifier<DateTime?> {
  ChatReadNotifier(this.roundId) : super(null) {
    _load();
  }

  final String roundId;

  String get _key => 'chat_last_read_$roundId';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s != null) state = DateTime.tryParse(s);
  }

  /// Setzt die „gelesen bis"-Marke; nur vorwärts (nie zurück).
  Future<void> markRead(DateTime at) async {
    if (state != null && !at.isAfter(state!)) return;
    state = at;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, at.toIso8601String());
  }
}

/// Gibt es ungelesene Chat-Nachrichten von anderen Mitgliedern? Grundlage
/// für den Hinweis am Liga-Symbol.
final unreadChatProvider = Provider.family<bool, String>((ref, roundId) {
  final myId = ref.watch(currentUserProvider)?.id;
  final lastRead = ref.watch(chatLastReadProvider(roundId));
  final messages =
      ref.watch(roundMessagesProvider(roundId)).valueOrNull ?? const [];
  return messages.any((m) =>
      m.userId != myId && (lastRead == null || m.createdAt.isAfter(lastRead)));
});

/// Alle sichtbaren Tipps einer Liga (fremde erst nach Anstoß).
final allRoundTipsProvider =
    FutureProvider.family<List<MemberTip>, String>((ref, roundId) {
  return ref.watch(tipRoundRepositoryProvider).allTips(roundId);
});

/// Abgegebene Bonustipp-Antworten einer Runde (alle Mitglieder).
final bonusAnswersProvider =
    FutureProvider.family<List<BonusAnswer>, String>((ref, roundId) {
  return ref.watch(tipRoundRepositoryProvider).bonusAnswers(roundId);
});

/// Existenz abgegebener Tipps (`userId|fixtureId`) — für das Schloss-Symbol
/// vor Anstoß (Gegner hat getippt), ohne den Tipp selbst zu zeigen.
final tipPresenceProvider =
    FutureProvider.family<Set<String>, String>((ref, roundId) {
  ref.watch(currentUserProvider);
  return ref.watch(tipRoundRepositoryProvider).tipPresence(roundId);
});

/// Punkteschema der aktiven Tipprunde, sonst Kicktipp-Standard.
final scoringRulesProvider = Provider<ScoringRules>((ref) {
  return ref.watch(activeRoundProvider)?.scoring ?? ScoringRules.kicktippDefault;
});

// ---------------------------------------------------------------------
// Tipps
// ---------------------------------------------------------------------

/// Roher Feldinhalt je Fixture, solange der Nutzer noch nicht
/// „Tipps speichern" gedrückt hat. Setzt sich beim Wechsel von Runde
/// oder Wettbewerb automatisch zurück, damit keine Eingaben in eine
/// fremde Runde übertragen werden.
final tipDraftProvider =
    StateNotifierProvider<TipDraftNotifier, Map<String, TipDraftEntry>>((ref) {
  ref.watch(activeRoundProvider);
  ref.watch(selectedLeagueProvider);
  return TipDraftNotifier();
});

/// Heim-/Auswärts-Feldinhalt eines noch nicht gespeicherten Tipps.
class TipDraftEntry {
  const TipDraftEntry(this.home, this.away);
  final String home;
  final String away;
}

class TipDraftNotifier extends StateNotifier<Map<String, TipDraftEntry>> {
  TipDraftNotifier() : super(const {});

  /// Merkt sich die aktuelle Eingabe; persistiert noch nichts.
  void edit(String fixtureId, String home, String away) {
    state = {...state, fixtureId: TipDraftEntry(home, away)};
  }

  /// Nach erfolgreichem Speichern eines Fixtures aus dem Entwurf nehmen.
  void clearEntry(String fixtureId) {
    if (!state.containsKey(fixtureId)) return;
    state = {...state}..remove(fixtureId);
  }
}

final tipsProvider =
    StateNotifierProvider<TipsNotifier, Map<String, Tip>>((ref) {
  final activeRound = ref.watch(activeRoundProvider);
  final user = ref.watch(currentUserProvider);

  if (AppConfig.isSupabaseConfigured && activeRound != null && user != null) {
    return TipsNotifier(
        SupabaseTipStore(Supabase.instance.client, activeRound.id));
  }
  // Außerhalb einer Liga (kein aktiver Round/Login) gibt es kein Tippen.
  return TipsNotifier(const EmptyTipStore());
});

class TipsNotifier extends StateNotifier<Map<String, Tip>> {
  TipsNotifier(this._store) : super(const {}) {
    _load();
  }

  final TipStore _store;

  Future<void> _load() async {
    final tips = await _store.load();
    if (mounted) state = tips;
  }

  /// Optimistisches Update; bei Ablehnung (z. B. Tippfrist) wird der
  /// alte Zustand wiederhergestellt und [TipRejected] weitergereicht.
  Future<void> setTip(String fixtureId, int homeGoals, int awayGoals) async {
    final previous = state;
    final tip = Tip(
        fixtureId: fixtureId, homeGoals: homeGoals, awayGoals: awayGoals);
    state = {...state, fixtureId: tip};
    try {
      await _store.save(tip);
    } catch (_) {
      if (mounted) state = previous;
      rethrow;
    }
  }

  Future<void> clearTip(String fixtureId) async {
    final previous = state;
    state = {...state}..remove(fixtureId);
    try {
      await _store.remove(fixtureId);
    } catch (_) {
      if (mounted) state = previous;
      rethrow;
    }
  }
}
