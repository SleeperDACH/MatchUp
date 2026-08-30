import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/aufstellung_uebernahme.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Die Elf der Vorwoche wird übernommen.**
///
/// Ohne das beginnt jeder Spieltag bei null. Nachgezählt beim Einbau: zwölf
/// Aufstellungen für Spieltag 1, **eine** für Spieltag 2 — elf Manager wären
/// leer in den Spieltag gegangen, ohne dass irgendetwas sie gewarnt hätte.
FantasyLineup _l(int runde, Set<String> ids) =>
    FantasyLineup(managerId: 'ich', round: runde, playerIds: ids);

void main() {
  final kader = {'a', 'b', 'c', 'd'};

  test('ohne jede Aufstellung gibt es nichts zu übernehmen', () {
    expect(uebernommeneElf(const [], 2, kader), isNull,
        reason: 'Dann schlägt der Schirm die beste Elf vor');
  });

  test('die Aufstellung dieses Spieltags schlägt alles andere', () {
    final elf = uebernommeneElf(
        [_l(1, {'a', 'b'}), _l(2, {'c', 'd'})], 2, kader);
    expect(elf, {'c', 'd'});
  });

  test('sonst zählt die Vorwoche', () {
    expect(uebernommeneElf([_l(1, {'a', 'b'})], 2, kader), {'a', 'b'});
  });

  test('ein ausgesetzter Spieltag fällt nicht aus der Übernahme', () {
    // **Nicht stur die Vorrunde.** Wer Spieltag 2 verpasst hat, soll an
    // Spieltag 3 seine Elf von Spieltag 1 wiederfinden, nicht einen Vorschlag.
    expect(uebernommeneElf([_l(1, {'a', 'b'})], 3, kader), {'a', 'b'});
  });

  test('die jüngere Aufstellung gewinnt', () {
    final elf = uebernommeneElf(
        [_l(1, {'a'}), _l(3, {'b'}), _l(2, {'c'})], 4, kader);
    expect(elf, {'b'});
  });

  test('wer nicht mehr im Kader ist, fällt raus', () {
    // Getradet, gedroppt oder über den Waiver weg: Der Platz bleibt leer.
    // Eine Elf mit einem fremden Spieler würde der Server ablehnen.
    expect(uebernommeneElf([_l(1, {'a', 'x', 'b'})], 2, kader), {'a', 'b'});
  });

  test('bleibt von der alten Elf nichts übrig, gibt es nichts zu übernehmen',
      () {
    expect(uebernommeneElf([_l(1, {'x', 'y'})], 2, kader), isNull);
  });

  test('eine leere Aufstellung zählt nicht als gestellt', () {
    expect(uebernommeneElf([_l(1, {'a'}), _l(2, const {})], 2, kader), {'a'},
        reason: 'Die leere Zeile für Spieltag 2 darf die Vorwoche nicht '
            'verdrängen');
  });
}
