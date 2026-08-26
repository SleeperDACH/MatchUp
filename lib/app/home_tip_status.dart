import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../features/auth/providers.dart';
import '../features/tippspiel/logic/tip_weeks.dart';
import '../features/tippspiel/providers.dart';

/// Offene Tipps einer Tipprunde — steht auf deren Karte auf dem Homescreen.
@immutable
class OffeneTipps {
  const OffeneTipps({required this.anzahl, this.frist});

  /// Noch nicht getippte Spiele der laufenden Spielwoche, die noch nicht
  /// angepfiffen sind.
  final int anzahl;

  /// Anstoß des nächsten offenen Spiels — das „bis wann". `null`, wenn in
  /// dieser Woche nichts mehr ansteht.
  final DateTime? frist;

  static const leer = OffeneTipps(anzahl: 0);
}

/// Offene Tipps je Runde (Family-Key ist die Runden-ID).
///
/// Gezählt wird über **dieselbe** Do–Mi-Woche, die auch der Tippen-Tab beim
/// Öffnen zeigt (`buildWeeks`/`currentWeekIndex`) — sonst stünden auf Karte
/// und Feed verschiedene Zahlen. Fehler werden zu „nichts offen": eine
/// hakelige Datenquelle darf die Karte nicht kippen.
final offeneTippsProvider = FutureProvider.family<OffeneTipps, String>((
  ref,
  roundId,
) async {
  if (!AppConfig.isSupabaseConfigured) return OffeneTipps.leer;
  final myId = ref.watch(currentUserProvider)?.id;
  if (myId == null) return OffeneTipps.leer;

  try {
    final rounds = await ref.watch(myRoundsProvider.future);
    final round = rounds.where((r) => r.id == roundId).firstOrNull;
    if (round == null) return OffeneTipps.leer;

    final all = <Fixture>[];
    for (final id in round.competitions) {
      all.addAll(await ref.watch(leagueSeasonFixturesProvider(id).future));
    }
    final weeks = buildWeeks(all);
    if (weeks.isEmpty) return OffeneTipps.leer;
    final now = DateTime.now();
    final index = currentWeekIndex(weeks, now);
    final week = weeks.firstWhere(
      (w) => w.index == index,
      orElse: () => weeks.last,
    );
    // `week.fixtures` ist nach Anstoß sortiert, `where` erhält die Reihenfolge.
    final offen = week.fixtures
        .where((f) => f.kickoff.toLocal().isAfter(now))
        .toList();
    if (offen.isEmpty) return OffeneTipps.leer;

    final tips = await ref.watch(allRoundTipsProvider(roundId).future);
    final meine = <String>{
      for (final t in tips)
        if (t.userId == myId) t.fixtureId,
    };
    final fehlend = offen.where((f) => !meine.contains(f.id)).toList();
    if (fehlend.isEmpty) return OffeneTipps.leer;
    return OffeneTipps(
      anzahl: fehlend.length,
      frist: fehlend.first.kickoff.toLocal(),
    );
  } catch (_) {
    return OffeneTipps.leer;
  }
});

/// „bis wann" in kurzer Form — die Karten sind schmal, und ein mitlaufender
/// Countdown wäre dort nur Unruhe. Bewusst absolute Zeiten statt Restdauer:
/// die veralten nicht, wenn die Karte eine Weile nicht neu gezeichnet wird.
String kurzeFrist(DateTime frist, DateTime jetzt) {
  if (!frist.isAfter(jetzt)) return 'abgelaufen';
  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final tag = DateTime(frist.year, frist.month, frist.day);
  final tageHin = tag.difference(heute).inDays;
  if (tageHin == 0) return 'bis ${DateFormat('HH:mm', 'de_DE').format(frist)}';
  if (tageHin == 1) {
    return 'bis morgen ${DateFormat('HH:mm', 'de_DE').format(frist)}';
  }
  if (tageHin < 7) {
    return 'bis ${DateFormat('E, HH:mm', 'de_DE').format(frist)}';
  }
  return 'bis ${DateFormat('d.M.', 'de_DE').format(frist)}';
}
