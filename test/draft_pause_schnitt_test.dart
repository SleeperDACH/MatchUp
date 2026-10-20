import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/draft_room_screen.dart';

/// Draft-Raum (19.10.2026): Pause mit Restzeit (0140) und der Schnitt in den
/// Spielerzeilen statt des Vereinsnamens.
void main() {
  group('Restzeit der Pause', () {
    test('liest Postgres-Intervalle', () {
      expect(intervallAusText('00:00:50'), const Duration(seconds: 50));
      expect(intervallAusText('01:30:00'), const Duration(minutes: 90));
      expect(intervallAusText('1 day 02:00:00'),
          const Duration(days: 1, hours: 2));
      expect(intervallAusText('00:00:12.345'), const Duration(seconds: 12));
      expect(intervallAusText(null), isNull);
    });
  });

  group('Schnitt im Draft-Raum', () {
    final p = FantasyPlayer(
      id: 'p1',
      name: 'Nico Schlotterbeck',
      position: PlayerPosition.def,
      club: 'Borussia Dortmund',
      nationality: 'de',
      birthDate: DateTime(1999, 12, 1),
    );
    const einsatz = PlayerMatchStats(minutes: 90, played: true, goals: 1);
    const regeln = FantasyScoringRules.standard;

    test('laufende Saison, sobald gewertet', () {
      final s = DraftSchnitte.aus(
        laufend: {
          1: {'p1': einsatz},
        },
        abgepfiffen: const [1],
        vorsaison: {
          30: {'p1': const PlayerMatchStats(minutes: 90, played: true)},
        },
        saison: 2026,
        regeln: regeln,
      );
      expect(s.zeile(p), startsWith('Abwehr · Ø '));
      expect(s.zeile(p), isNot(contains('25/26')));
    });

    test('vor dem ersten Spieltag die Vorsaison, mit Jahr', () {
      final s = DraftSchnitte.aus(
        laufend: const {},
        abgepfiffen: const [],
        vorsaison: {
          30: {'p1': einsatz},
        },
        saison: 2026,
        regeln: regeln,
      );
      expect(s.zeile(p), startsWith('Abwehr · Ø 25/26 '));
    });

    test('ohne jede Statistik nur die Position, kein Vereinsname', () {
      final s = DraftSchnitte.aus(
        laufend: null,
        abgepfiffen: const [],
        vorsaison: null,
        saison: 2026,
        regeln: regeln,
      );
      expect(s.zeile(p), 'Abwehr');
    });
  });
}
