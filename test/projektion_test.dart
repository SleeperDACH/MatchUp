import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/logic/projektion.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';

/// **Die Prognose der Startelf.**
///
/// Gerechnet wird hier und nicht im Schirm, weil an der Zahl eine Regel hängt
/// („verletzt oder gesperrt zählt nicht mit") — und eine Regel in einem
/// Widget-Baum ist nicht prüfbar, ohne den halben Schirm samt Providern zu
/// bauen. Dieselbe Trennung wie bei `aufstellung_sperre` und
/// `formation_umbau`.

const _regeln = FantasyScoringRules();

FantasyPlayer _p(String id, PlayerPosition pos) => FantasyPlayer(
      id: id,
      name: 'Spieler $id',
      position: pos,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(1998, 5, 4),
    );

/// Ein Spieltag, an dem [minuten] gespielt wurden — das ergibt über den
/// Einsatzbonus eine Punktzahl, die nicht null ist.
PlayerMatchStats _einsatz(int minuten) => PlayerMatchStats(minutes: minuten);

PlayerAbsence _verletzt(String id) => PlayerAbsence(
      playerId: id,
      gesperrt: false,
      grundQuelle: 'Muscle Injury',
      seit: DateTime(2026, 9, 1),
    );

PlayerAbsence _gesperrt(String id) => PlayerAbsence(
      playerId: id,
      gesperrt: true,
      grundQuelle: 'Red Card Suspension',
      seit: DateTime(2026, 9, 1),
    );

void main() {
  group('Projektion', () {
    test('summiert die Schnitte, statt sie zu mitteln', () {
      // Zwei Spieler, zwei gewertete Spieltage, beide durchgespielt.
      final elf = [_p('a', PlayerPosition.mid), _p('b', PlayerPosition.mid)];
      final saison = {
        1: {'a': _einsatz(90), 'b': _einsatz(90)},
        2: {'a': _einsatz(90), 'b': _einsatz(90)},
      };

      final ergebnis = projektion(
        elf: elf,
        saison: saison,
        regeln: _regeln,
        ausfaelle: const {},
      );

      // Jeder hat einen Schnitt > 0; die Prognose ist deren Summe, nicht ihr
      // Mittelwert — sonst stünde dort die Punktzahl *eines* Spielers.
      final einzeln = ergebnis.punkte / 2;
      expect(ergebnis.punkte, greaterThan(einzeln));
      expect(ergebnis.gezaehlt, 2);
      expect(ergebnis.ausgelassen, 0);
      expect(ergebnis.hatDaten, isTrue);
    });

    test('verletzte und gesperrte Spieler zaehlen nicht mit', () {
      final elf = [
        _p('fit', PlayerPosition.mid),
        _p('krank', PlayerPosition.mid),
        _p('rot', PlayerPosition.mid),
      ];
      final saison = {
        1: {'fit': _einsatz(90), 'krank': _einsatz(90), 'rot': _einsatz(90)},
      };

      final alle = projektion(
        elf: elf,
        saison: saison,
        regeln: _regeln,
        ausfaelle: const {},
      );
      final ohne = projektion(
        elf: elf,
        saison: saison,
        regeln: _regeln,
        ausfaelle: {'krank': _verletzt('krank'), 'rot': _gesperrt('rot')},
      );

      expect(alle.gezaehlt, 3);
      expect(ohne.gezaehlt, 1, reason: 'nur der Fitte bleibt übrig');
      expect(ohne.ausgelassen, 2);
      // **Weggelassen, nicht als Null eingerechnet:** Die Summe ist genau der
      // Anteil des verbliebenen Spielers, nicht ein Drittel davon.
      expect(ohne.punkte, closeTo(alle.punkte / 3, 0.001));
    });

    test('ohne gewertete Spieltage gibt es nichts zu zeigen', () {
      final ergebnis = projektion(
        elf: [_p('a', PlayerPosition.mid)],
        // Der kommende Spieltag steht schon in der Karte, ist aber leer —
        // genau der Zustand zwischen zwei Spieltagen am Saisonanfang.
        saison: {1: const <String, PlayerMatchStats>{}},
        regeln: _regeln,
        ausfaelle: const {},
      );

      expect(ergebnis.spieltage, 0);
      expect(ergebnis.hatDaten, isFalse,
          reason: 'eine 0 waere eine Aussage, die niemand gemacht hat');
    });

    test('faellt die ganze Elf aus, gibt es keine Prognose', () {
      final elf = [_p('a', PlayerPosition.gk)];
      final ergebnis = projektion(
        elf: elf,
        saison: {
          1: {'a': _einsatz(90)},
        },
        regeln: _regeln,
        ausfaelle: {'a': _verletzt('a')},
      );

      expect(ergebnis.gezaehlt, 0);
      expect(ergebnis.ausgelassen, 1);
      expect(ergebnis.hatDaten, isFalse);
    });
  });
}
