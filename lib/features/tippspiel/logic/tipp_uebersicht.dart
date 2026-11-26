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
    this.spieltag = const [],
    this.spieltagWoche,
  });

  /// Eigener Platz; `null`, wenn man (noch) nicht Mitglied ist.
  final int? rang;
  final int mitglieder;
  final int punkte;

  /// Eigene Punkte am [spieltagWoche], laufende Spiele eingerechnet.
  final int wochePunkte;

  /// Noch nicht getippte Spiele der Woche, die noch nicht angepfiffen sind.
  final int offen;

  /// Alle Spiele der Woche, die noch nicht angepfiffen sind.
  final int anstehend;

  /// Anpfiff des ersten ungetippten Spiels — bis dahin muss getippt sein.
  final DateTime? frist;

  /// Die ersten drei, und der eigene Platz, falls er nicht dabei ist.
  final List<UebersichtPlatz> kurztabelle;

  /// **Punkte aller Teilnehmer am Spieltag** (26.11.2026), beste zuerst.
  /// Leer beim Globalen Tippspiel — die App kennt dort nur einen Ausschnitt
  /// der Mitglieder, eine Spieltagswertung daraus wäre falsch.
  final List<UebersichtPlatz> spieltag;

  /// Die Woche, deren Punkte [spieltag] und [wochePunkte] zeigen — ab 24 h
  /// vor ihrem ersten Anstoß (siehe [aktuelleSpieltagWoche]); `null` vor der Saison.
  final TipWeek? spieltagWoche;

  static TippUebersicht berechnen({
    required List<RoundMember> members,
    required List<MemberTip> tips,
    required List<Fixture> seasonFixtures,
    required ScoringRules rules,
    required String? myId,
    required DateTime jetzt,
    Map<String, FrozenOdds> frozenOdds = const {},
    int oben = 3,
    // Globales Tippspiel: Plätze und Mitgliederzahl vom Server (0169), weil
    // [members] dort nur der Ausschnitt ist.
    Map<String, int>? raenge,
    int? mitgliederGesamt,
  }) {
    final totals = totalPointsByMember(
      members: members,
      tips: tips,
      fixtures: seasonFixtures,
      rules: rules,
      frozenOdds: frozenOdds,
    );
    final ranks = raenge ?? ranksByPoints(members, totals);
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

    // Spieltag: eigene Woche mit eigenem Wechsel (24 h vor dem nächsten).
    final stWoche = aktuelleSpieltagWoche(wochen, jetzt);
    final stPunkte = stWoche == null
        ? <String, int>{}
        : totalPointsByMember(
            members: members,
            tips: tips,
            fixtures: stWoche.fixtures,
            rules: rules,
            frozenOdds: frozenOdds,
          );
    final spieltag = <UebersichtPlatz>[];
    if (stWoche != null && raenge == null) {
      final stRaenge = ranksByPoints(members, stPunkte);
      final reihe = [...members]..sort((a, b) {
          final r = (stRaenge[a.userId] ?? 0) - (stRaenge[b.userId] ?? 0);
          return r != 0
              ? r
              : a.display.toLowerCase().compareTo(b.display.toLowerCase());
        });
      for (final m in reihe) {
        spieltag.add(UebersichtPlatz(
          rang: stRaenge[m.userId] ?? 0,
          mitglied: m,
          punkte: stPunkte[m.userId] ?? 0,
          ich: m.userId == myId,
        ));
      }
    }

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
      // Dieselbe Zahl wie in der Spieltag-Liste, nicht die Tipp-Woche —
      // sonst stünde dort „+5" und darüber „0 diese Woche".
      wochePunkte = stPunkte[ich.userId] ?? 0;
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
      mitglieder: mitgliederGesamt ?? members.length,
      punkte: ich == null ? 0 : (totals[ich.userId] ?? 0),
      wochePunkte: wochePunkte,
      offen: offen,
      anstehend: anstehend,
      frist: frist,
      kurztabelle: kurz,
      spieltag: spieltag,
      spieltagWoche: stWoche,
    );
  }
}
