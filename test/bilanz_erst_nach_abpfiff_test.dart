import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/round_robin.dart';
import 'package:matchup/features/fantasy/providers.dart';

/// **Eine Bilanz ist ein Ergebnis, kein Zwischenstand.**
///
/// Gemeldet: *„Im MatchUp-Bereich steht schon eine Niederlage bei SFV, obwohl
/// der Spieltag ja noch gar nicht vorbei ist. Das macht keinen Sinn."*
///
/// Die Bilanz lief über **alle** Runden mit Statistikzeilen — und die gibt es
/// für den laufenden Spieltag schon mittags, sobald die ersten Partien
/// angepfiffen sind. Wer am Samstag um 16 Uhr hinten lag, hatte dort eine
/// Niederlage stehen, die sich bis Sonntagabend noch drehen konnte.
///
/// Der laufende Spieltag hat seinen eigenen Ort: die Live-Punkte im
/// MatchUp-Kasten, die dort auch so heißen.
void main() {
  group('gewerteteRunden', () {
    test('der laufende Spieltag zählt nicht mit', () {
      // Spieltag 1 und 2 sind abgepfiffen, für 3 liegen schon Zahlen vor.
      final gewertet = gewerteteRunden([1, 2], [1, 2, 3]);
      expect(gewertet, {1, 2});
      expect(gewertet.contains(3), isFalse,
          reason: 'Spieltag 3 läuft noch — sein Ergebnis steht nicht fest');
    });

    test('ein abgepfiffener Spieltag ohne Daten zählt auch nicht', () {
      // Der Spielplan sagt „fertig", die Statistik hat noch nichts. Ihn
      // mitzuzählen hieße, allen null Punkte zu geben — und daraus würde ein
      // Unentschieden, das nie gespielt wurde.
      expect(gewerteteRunden([1, 2, 3], [1, 2]), {1, 2});
    });

    test('ohne abgepfiffene Spieltage bleibt die Bilanz leer', () {
      expect(gewerteteRunden(const [], [1, 2, 3]), isEmpty);
    });
  });

  group('Reihenfolge der Bilanz', () {
    // **Sieg – Unentschieden – Niederlage** (auf Ansage, 05.09.2026). Vorher
    // stand im MatchUp-Kasten und im Tippspiel-Duell S-N-U. Jede Tabelle
    // dieser App liest sich S·U·N, und wer „2-1-3" sieht, rechnet sie
    // automatisch so — die alte Reihenfolge machte aus einem Manager mit drei
    // Niederlagen einen mit drei Unentschieden.
    test('drei verschiedene Zahlen lassen sich nicht verwechseln', () {
      const r = H2HRecord(managerId: 'm1', wins: 2, ties: 1, losses: 3);
      expect('${r.wins}-${r.ties}-${r.losses}', '2-1-3');
      expect(r.played, 6);
      expect(r.points, 7, reason: '2 Siege à 3 plus ein Unentschieden');
    });
  });
}
