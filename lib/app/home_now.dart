import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/fantasy/logic/draft_order.dart';
import '../features/fantasy/models/fantasy_models.dart';
import '../features/fantasy/providers.dart';
import '../features/tippspiel/logic/tip_weeks.dart';
import '../features/tippspiel/models/tip_round.dart';
import '../features/tippspiel/providers.dart';

/// Art der anstehenden Sache — bestimmt Farbe, Text und Knopf der Jetzt-Karte.
enum NowKind {
  /// Ein Draft läuft gerade (Pick-Uhr tickt).
  draft,

  /// In einer Tipprunde sind Spiele der laufenden Woche noch ungetippt.
  tips,

  /// Alles getippt — es läuft nur noch die Uhr bis zum nächsten Anstoß.
  kickoff,
}

/// Was gerade ansteht. Genau ein Eintrag steht oben auf dem Homescreen;
/// die Auswahl trifft [nowItemProvider].
@immutable
class NowItem {
  const NowItem({
    required this.kind,
    required this.label,
    this.detail,
    this.deadline,
    this.round,
    this.league,
    this.openTips = 0,
    this.myTurn = false,
  });

  final NowKind kind;

  /// Name der Liga bzw. Tipprunde — sagt, wohin der Knopf führt.
  final String label;

  /// Zweite Zeile, z. B. „Spieltag 3" oder „Runde 4 · Pick 27".
  final String? detail;

  /// Anstoß des nächsten Spiels bzw. Ende der Pick-Zeit; `null` = keine Uhr
  /// (Drafts ohne Zeitlimit).
  final DateTime? deadline;

  /// Ziel bei [NowKind.tips] / [NowKind.kickoff].
  final TipRound? round;

  /// Ziel bei [NowKind.draft].
  final FantasyLeague? league;

  final int openTips;

  /// Beim Draft: der eigene Pick ist dran.
  final bool myTurn;
}

/// Die eine Sache, die gerade ansteht. `null` = nichts Dringendes (oder kein
/// Server/keine Anmeldung) — dann bleibt die Karte weg.
///
/// Reihenfolge: ein laufender Draft schlägt alles (seine Pick-Uhr läuft in
/// Minuten ab), danach die dringendste Tipp-Deadline. Fehler einzelner Ligen
/// werden übersprungen statt hochgereicht: eine hakelige Datenquelle darf den
/// Homescreen nicht leeren.
final nowItemProvider = FutureProvider<NowItem?>((ref) async {
  if (!AppConfig.isSupabaseConfigured) return null;
  final myId = ref.watch(currentUserProvider)?.id;
  if (myId == null) return null;

  final draft = await _draftItem(ref, myId);
  if (draft != null) return draft;
  return _tipItem(ref, myId);
});

/// Laufender Draft; ist der eigene Pick dran, gewinnt diese Liga.
Future<NowItem?> _draftItem(Ref ref, String myId) async {
  final List<FantasyLeague> leagues;
  try {
    leagues = await ref.watch(myFantasyLeaguesProvider.future);
  } catch (_) {
    return null;
  }
  NowItem? fallback;
  for (final l in leagues) {
    if (l.draftStatus != DraftStatus.drafting) continue;
    List<FantasyManager> managers;
    try {
      managers = await ref.watch(fantasyManagersProvider(l.id).future);
    } catch (_) {
      managers = const [];
    }
    final current = currentManager(managers, l.picksMade);
    final mine = current != null && current.userId == myId;
    final round =
        managers.isEmpty ? 1 : l.picksMade ~/ managers.length + 1;
    final item = NowItem(
      kind: NowKind.draft,
      label: l.name,
      detail: 'Runde $round · Pick ${l.picksMade + 1}',
      deadline: l.currentPickDeadline,
      league: l,
      myTurn: mine,
    );
    if (mine) return item;
    fallback ??= item;
  }
  return fallback;
}

/// Dringendste Tipp-Deadline über alle Tipprunden.
Future<NowItem?> _tipItem(Ref ref, String myId) async {
  final List<TipRound> rounds;
  try {
    rounds = await ref.watch(myRoundsProvider.future);
  } catch (_) {
    return null;
  }
  final now = DateTime.now();
  NowItem? best;
  for (final r in rounds) {
    try {
      final all = <Fixture>[];
      for (final id in r.competitions) {
        all.addAll(await ref.watch(leagueSeasonFixturesProvider(id).future));
      }
      final weeks = buildWeeks(all);
      if (weeks.isEmpty) continue;
      // Dieselbe Woche, die der Tippen-Tab beim Öffnen zeigt.
      final index = currentWeekIndex(weeks, now);
      final week = weeks.firstWhere((w) => w.index == index,
          orElse: () => weeks.last);
      // `week.fixtures` ist nach Anstoß sortiert, `where` erhält die Reihenfolge.
      final open =
          week.fixtures.where((f) => f.kickoff.toLocal().isAfter(now)).toList();
      if (open.isEmpty) continue;
      final tips = await ref.watch(allRoundTipsProvider(r.id).future);
      final mine = <String>{
        for (final t in tips)
          if (t.userId == myId) t.fixtureId
      };
      final missing = open.where((f) => !mine.contains(f.id)).length;
      final next = open.first;
      final item = NowItem(
        kind: missing > 0 ? NowKind.tips : NowKind.kickoff,
        label: r.name,
        detail: r.competitions.length > 1
            ? 'Spielwoche ${week.index}'
            : _spieltagLabel(next.roundName),
        deadline: next.kickoff.toLocal(),
        round: r,
        openTips: missing,
      );
      if (best == null || _moreUrgent(item, best)) best = item;
    } catch (_) {
      continue; // Eine Liga ohne Daten darf die Karte nicht kippen.
    }
  }
  return best;
}

/// OpenLigaDB liefert als Rundennamen teils nur die Zahl („1"). Allein steht
/// die nackt in der Karte — dann davor „Spieltag" setzen.
String _spieltagLabel(String roundName) {
  final n = int.tryParse(roundName.trim());
  return n == null ? roundName : 'Spieltag $n';
}

/// Offene Tipps gehen vor „alles getippt"; darin entscheidet der frühere
/// Anstoß.
bool _moreUrgent(NowItem a, NowItem b) {
  if ((a.kind == NowKind.tips) != (b.kind == NowKind.tips)) {
    return a.kind == NowKind.tips;
  }
  final ad = a.deadline;
  final bd = b.deadline;
  if (ad == null) return false;
  if (bd == null) return true;
  return ad.isBefore(bd);
}
