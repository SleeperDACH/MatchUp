import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/rueckkehr.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';

/// **Wann ist er wieder da?**
///
/// Gewünscht: *„Wenn ein Spieler verletzt ist, wird die voraussichtliche
/// Rückkehr angezeigt … Wenn es nicht bekannt ist, dann Rückkehr unbekannt."*
///
/// Die Quelle kennt genau ein Feld dafür und füllt es selten: gemessen 24 von
/// 109 Ausfällen. Der häufigste Fall ist deshalb der unbekannte, und er muss
/// als eigener Zustand dastehen — nicht als leere Zeile.

Fixture _f(String heim, String gast, DateTime anstoss, int runde) => Fixture(
      id: 'sportmonks:$heim$runde',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: '$runde. Spieltag',
      kickoff: anstoss,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      status: FixtureStatus.scheduled,
    );

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  final jetzt = DateTime(2026, 9, 7, 12);

  group('rueckkehrSatz', () {
    test('ohne Datum: die ehrliche Auskunft', () {
      expect(rueckkehrSatz(null, jetzt), 'Rückkehr unbekannt');
    });

    test('in Tagen, wenn es nah ist', () {
      expect(rueckkehrSatz(DateTime(2026, 9, 12), jetzt),
          'Zurück ab 12. September · in 5 Tagen');
    });

    test('heute und morgen bekommen Wörter, keine Zahlen', () {
      expect(rueckkehrSatz(DateTime(2026, 9, 7), jetzt), 'Zurück ab heute');
      expect(rueckkehrSatz(DateTime(2026, 9, 8), jetzt), 'Zurück ab morgen');
    });

    test('in Wochen, grob', () {
      // **Grob ist Absicht.** Das Datum ist eine Schätzung der Quelle; „in 23
      // Tagen" täuschte eine Genauigkeit vor, die dahinter nicht steckt.
      expect(rueckkehrSatz(DateTime(2026, 9, 30), jetzt),
          'Zurück ab 30. September · in etwa 3 Wochen');
    });

    test('in Monaten, wenn es weit weg ist', () {
      expect(rueckkehrSatz(DateTime(2027, 1, 28), jetzt),
          'Zurück ab 28. Januar · in etwa 5 Monaten');
    });

    test('ein vergangenes Datum ist eine Verzögerung, keine Rückkehr', () {
      // Die Quelle schreibt es nicht zurück. Er sollte längst spielen und tut
      // es nicht — „zurück ab 1. September" wäre schlicht falsch.
      expect(rueckkehrSatz(DateTime(2026, 9, 1), jetzt),
          'Rückkehr war für den 1. September geplant');
    });
  });

  group('ersterSpieltagAb', () {
    final spielplan = [
      _f('Borussia Dortmund', 'Hamburger SV', DateTime(2026, 9, 12, 15, 30), 3),
      _f('1. FC Köln', 'Borussia Dortmund', DateTime(2026, 9, 19, 15, 30), 4),
      _f('Borussia Dortmund', 'FC Bayern München', DateTime(2026, 10, 3, 18, 30), 5),
    ];

    test('nennt den ersten Spieltag ab dem Tag', () {
      expect(ersterSpieltagAb(DateTime(2026, 9, 15), spielplan,
          'Borussia Dortmund'), 4);
    });

    test('ein Spiel am selben Tag zählt mit', () {
      expect(ersterSpieltagAb(DateTime(2026, 9, 12), spielplan,
          'Borussia Dortmund'), 3);
    });

    test('die Schreibweise des Vereins darf abweichen', () {
      // Kader und Spielplan schreiben denselben Verein verschieden — genau
      // daran hing der Waiver-Fehler aus Migration 0108.
      final koeln = [
        _f('1. FC Köln', 'Borussia Dortmund', DateTime(2026, 9, 19, 15, 30), 4),
      ];
      expect(ersterSpieltagAb(DateTime(2026, 9, 15), koeln, 'FC Köln'), 4);
    });

    test('kein Spiel mehr: lieber nichts als eine geratene Zahl', () {
      expect(ersterSpieltagAb(DateTime(2027, 5, 1), spielplan,
          'Borussia Dortmund'), isNull);
      expect(ersterSpieltagAb(DateTime(2026, 9, 15), spielplan,
          'SV Werder Bremen'), isNull);
    });
  });

  test('der beobachtete Ausfall kennt keine Rückkehr', () {
    // Ein Wechsel-Ereignis sagt, dass jemand verletzt vom Platz ging. Wann er
    // wiederkommt, sagt es nicht — und das muss dastehen.
    final a = PlayerAbsence.fromJson({
      'player_id': 'sportmonks:37602269',
      'kategorie': 'injury',
      'grund_quelle': 'Substituted Off Injured',
      'quelle': 'ausgewechselt',
      'runde': 2,
      'minute': 32,
    });
    expect(a.bis, isNull);
    expect(rueckkehrSatz(a.bis, jetzt), 'Rückkehr unbekannt');
  });
}
