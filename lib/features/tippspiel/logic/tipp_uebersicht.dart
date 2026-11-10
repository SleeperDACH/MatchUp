import '../../../core/data/odds/frozen_odds.dart';
import '../../../core/models/models.dart';
import '../models/tip_round.dart';
import '../models/tip.dart';
import 'round_table.dart';
import 'tip_weeks.dart';

/// Ein Platz in der Kurztabelle der Übersicht.
class UebersichtPlatz {
  const UebersichtPlatz({
    required this.rang,
    required this.mitglied,
    required this.punkte,
    required this.ich,
  });

  final int rang;
  final RoundMember mitglied;
  final int punkte;
  final bool ich;
}

/// **Was die Tippspiel-Übersicht zeigt** (09.11.2026, „Richtung B" aus dem
/// Redesign: Reiter oben wie bei Fantasy, die Übersicht als Einstieg).
///
/// Pur, damit Zahlen und Kurztabelle ohne Schirm prüfbar sind. Gerechnet wird
/// mit **derselben** Wertung wie die Tabelle ([totalPointsByMember],
/// [ranksByPoints]) und derselben Do–Mi-Woche wie der Tippen-Reiter
/// ([buildWeeks], [currentWeekIndex]) — sonst stünde in der Übersicht eine
/// andere Zahl als einen Reiter weiter.
class TippUebersicht {
  const TippUebersicht({
    required this.rang,
    required this.mitglieder,
    required this.punkte,
    required this.wochePunkte,
    required this.offen,
    required this.anstehend,
    required this.frist,
    required this.kurztabelle,
  });

  /// Eigener Platz; `null`, wenn man (noch) nicht Mitglied ist.
  final int? rang;
  final int mitglieder;
  final int punkte;

  /// Punkte aus den Spielen der aktuellen Woche, laufende eingerechnet.
  final int wochePunkte;

  /// Noch nicht getippte Spiele der Woche, die noch nicht angepfiffen sind.
  final int offen;

  /// Alle Spiele der Woche, die noch nicht angepfiffen sind.
  final int anstehend;

  /// Anpfiff des ersten ungetippten Spiels — bis dahin muss getippt sein.
  final DateTime? frist;

  /// Die ersten drei, und der eigene Platz, falls er nicht dabei ist.
  final List<UebersichtPlatz> kurztabelle;

  static TippUebersicht berechnen({
    required List<RoundMember> members,
    required List<MemberTip> tips,
    required List<Fixture> seasonFixtures,
    required ScoringRules rules,
    required String? myId,
    required DateTime jetzt,
    Map<String, FrozenOdds> frozenOdds = const {},
    int oben = 3,
  }) {
    final totals = totalPointsByMember(
      members: members,
      tips: tips,
      fixtures: seasonFixtures,
      rules: rules,
      frozenOdds: frozenOdds,
    );
    final ranks = ranksByPoints(members, totals);
    final sortiert = [...members]
      ..sort((a, b) {
        final r = (ranks[a.userId] ?? 0) - (ranks[b.userId] ?? 0);
        return r != 0
            ? r
            : a.display.toLowerCase().compareTo(b.display.toLowerCase());
      });

    final kurz = <UebersichtPlatz>[];
    for (final m in sortiert.take(oben)) {
      kurz.add(UebersichtPlatz(
        rang: ranks[m.userId] ?? 0,
        mitglied: m,
        punkte: totals[m.userId] ?? 0,
        ich: m.userId == myId,
      ));
    }
    final ichDrin = kurz.any((p) => p.ich);
    final ich = members.where((m) => m.userId == myId).firstOrNull;
    if (!ichDrin && ich != null) {
      kurz.add(UebersichtPlatz(
        rang: ranks[ich.userId] ?? 0,
        mitglied: ich,
        punkte: totals[ich.userId] ?? 0,
        ich: true,
      ));
    }

    // Die Woche, die auch der Tippen-Reiter öffnet.
    final wochen = buildWeeks(seasonFixtures);
    var wochePunkte = 0;
    var offen = 0;
    var anstehend = 0;
    DateTime? frist;
    if (wochen.isNotEmpty && ich != null) {
      // `currentWeekIndex` liefert die **1-basierte Wochennummer**, nicht
      // die Position in der Liste — ausgewählt wird wie im Tippen-Reiter.
      final nummer = currentWeekIndex(wochen, jetzt);
      final woche = wochen.firstWhere(
        (w) => w.index == nummer,
        orElse: () => wochen.last,
      );
      wochePunkte = totalPointsByMember(
            members: [ich],
            tips: tips,
            fixtures: woche.fixtures,
            rules: rules,
            frozenOdds: frozenOdds,
          )[ich.userId] ??
          0;
      final meine = {
        for (final t in tips)
          if (t.userId == ich.userId) t.fixtureId,
      };
      final kommend = [
        for (final f in woche.fixtures)
          if (f.kickoff.isAfter(jetzt)) f,
      ]..sort((a, b) => a.kickoff.compareTo(b.kickoff));
      anstehend = kommend.length;
      for (final f in kommend) {
        if (meine.contains(f.id)) continue;
        offen++;
        frist ??= f.kickoff.toLocal();
      }
    }

    return TippUebersicht(
      rang: ich == null ? null : ranks[ich.userId],
      mitglieder: members.length,
      punkte: ich == null ? 0 : (totals[ich.userId] ?? 0),
      wochePunkte: wochePunkte,
      offen: offen,
      anstehend: anstehend,
      frist: frist,
      kurztabelle: kurz,
    );
  }
}
