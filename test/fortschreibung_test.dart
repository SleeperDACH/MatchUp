import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/aufstellungs_prognose.dart';
import 'package:matchup/features/fantasy/logic/fortschreibung.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/player_absence.dart';

/// **Die Elf der Vorwoche, bis die echte Prognose kommt.**
///
/// Jeder Fall hier ist eine Zusage an den Nutzer: Es steht eine Elf da (statt
/// drei Tage nichts), es steht niemand darin, der nicht kann, und es behauptet
/// nichts, was es nicht weiß.
FantasyPlayer _p(String id, String name, PlayerPosition pos,
        {bool weg = false}) =>
    FantasyPlayer(
      id: id,
      name: name,
      position: pos,
      club: 'FC Test',
      birthDate: DateTime(1999),
      nationality: 'DE',
      abgangAm: weg ? DateTime(2026, 9, 1) : null,
    );

PrognoseSpieler _s(String id, String name, int reihe, int spalte) =>
    PrognoseSpieler(
      playerId: id,
      name: name,
      nummer: 7,
      formationsPosition: reihe * 10 + spalte,
      reihe: reihe,
      spalte: spalte,
    );

/// Eine gemeldete 4-4-2 mit benannten Plätzen.
PrognoseElf _gemeldeteElf() => PrognoseElf(
      club: 'FC Test',
      bestaetigt: true,
      formation: '4-4-2',
      elf: [
        _s('tw', 'Torwart Eins', 1, 1),
        for (var i = 1; i <= 4; i++) _s('abw$i', 'Abwehr $i', 2, i),
        for (var i = 1; i <= 4; i++) _s('mf$i', 'Mittelfeld $i', 3, i),
        for (var i = 1; i <= 2; i++) _s('st$i', 'Sturm $i', 4, i),
      ],
      bank: [
        PrognoseSpieler(
            playerId: 'abw5', name: 'Abwehr 5', nummer: 23, bank: true),
      ],
    );

List<FantasyPlayer> _kader() => [
      _p('tw', 'Torwart Eins', PlayerPosition.gk),
      _p('tw2', 'Torwart Zwei', PlayerPosition.gk),
      for (var i = 1; i <= 5; i++)
        _p('abw$i', 'Abwehr $i', PlayerPosition.def),
      for (var i = 1; i <= 5; i++)
        _p('mf$i', 'Mittelfeld $i', PlayerPosition.mid),
      for (var i = 1; i <= 3; i++)
        _p('st$i', 'Sturm $i', PlayerPosition.fwd),
    ];

void main() {
  group('fortgeschriebeneElf', () {
    test('ohne Ausfälle steht die Elf der Vorwoche unverändert da', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: _kader(),
        faelltAus: const {},
        minuten: const {},
      )!;

      expect(elf.elf.length, 11);
      expect(elf.elf.map((s) => s.playerId).toList(),
          _gemeldeteElf().elf.map((s) => s.playerId).toList());
      expect(elf.elf.any((s) => s.ersatz), isFalse);
      expect(elf.ausRunde, 2);
      expect(elf.fortgeschrieben, isTrue);
      // **Sie gibt sich nie als Meldung aus.** `bestaetigt` bliebe sonst von
      // der Vorwoche stehen, und die Oberfläche schriebe „In der Startelf"
      // über ein Spiel, das erst kommt.
      expect(elf.bestaetigt, isFalse);
    });

    test('ein Verletzter wird durch den nominellen Ersatz getauscht', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: _kader(),
        faelltAus: const {'abw2'},
        // Abwehr 5 hat mehr Minuten als der Rest der Bank — er ist der
        // nominelle Ersatz, nicht der alphabetisch erste.
        minuten: const {'abw5': 400},
      )!;

      expect(elf.elf.length, 11, reason: 'die Elf bleibt vollständig');
      expect(elf.elf.any((s) => s.playerId == 'abw2'), isFalse);

      final rein = elf.elf.firstWhere((s) => s.ersatz);
      expect(rein.playerId, 'abw5');
      expect(rein.fuer, 'Abwehr 2');
      // **Er erbt den Platz im Raster** — sonst fiele die Formation beim
      // ersten Ausfall in eine einzige Reihe zusammen.
      expect(rein.reihe, 2);
      expect(rein.spalte, 2);
      // Die Rückennummer kommt aus der Bank derselben Meldung.
      expect(rein.nummer, 23);
    });

    test('gesperrt, angeschlagen und abgewandert zählen gleich', () {
      final kader = [
        ..._kader().where((p) => p.id != 'mf5'),
        _p('mf5', 'Mittelfeld 5', PlayerPosition.mid, weg: true),
      ];
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: kader,
        faelltAus: const {'mf1'},
        minuten: const {'mf5': 900},
      )!;

      // **Der Abgewanderte darf trotz der meisten Minuten nicht nachrücken.**
      // Er steht für keinen Verein mehr auf dem Platz (Migration 0117) — und
      // weil er der einzige freie Mittelfeldspieler war, bleibt der Platz
      // lieber leer, als dass er ihn füllt.
      expect(elf.elf.any((s) => s.playerId == 'mf5'), isFalse);
      expect(elf.elf.any((s) => s.playerId == 'mf1'), isFalse);
      expect(elf.elf.any((s) => s.ersatz), isFalse);
      expect(elf.elf.where((s) => s.offen).length, 1);
      expect(elf.elf.length, 11);
    });

    test('niemand rückt auf zwei Plätze gleichzeitig nach', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: _kader(),
        faelltAus: const {'mf1', 'mf2'},
        minuten: const {'mf5': 500},
      )!;

      final ids = elf.elf.map((s) => s.playerId).toList();
      expect(ids.toSet().length, ids.length, reason: 'keine Dublette');
      expect(elf.elf.where((s) => s.ersatz).length, 1,
          reason: 'nur ein freier Mittelfeldspieler im Kader');
      expect(elf.elf.where((s) => s.offen).length, 1);
    });

    test('ohne freien Ersatz bleibt der Platz sichtbar leer', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        // Nur ein Torwart im Kader — für ihn gibt es keinen Ersatz.
        vereinsKader: _kader().where((p) => p.id != 'tw2').toList(),
        faelltAus: const {'tw'},
        minuten: const {},
      )!;

      final platz = elf.elf.firstWhere((s) => s.offen);
      // **Lieber sichtbar leer als ein Stürmer im Tor.** Ein Ersatz aus einem
      // fremden Positionsraum wäre geraten, und geraten sieht aus wie gewusst.
      expect(platz.playerId, '');
      expect(platz.fuer, 'Torwart Eins');
      expect(platz.reihe, 1);
      expect(elf.elf.length, 11, reason: 'der Platz bleibt im Raster stehen');
    });

    test('aus einer bloßen Prognose wird nichts fortgeschrieben', () {
      final nurPrognose = PrognoseElf(
        club: 'FC Test',
        bestaetigt: false,
        elf: _gemeldeteElf().elf,
      );
      // Eine Schätzung fortzuschreiben hieße, sie als Tatsache auszugeben.
      expect(
        fortgeschriebeneElf(
          letzte: nurPrognose,
          ausRunde: 2,
          vereinsKader: _kader(),
          faelltAus: const {},
          minuten: const {},
        ),
        isNull,
      );
    });

    test('die Bank der Vorwoche wird nicht mitgeschleppt', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: _kader(),
        faelltAus: const {},
        minuten: const {},
      )!;
      // Sie war eine Aussage über ein gelaufenes Spiel; für den kommenden
      // Spieltag weiß sie niemand.
      expect(elf.bank, isEmpty);
    });

    test('die Formation der Vorwoche bleibt lesbar', () {
      final elf = fortgeschriebeneElf(
        letzte: _gemeldeteElf(),
        ausRunde: 2,
        vereinsKader: _kader(),
        faelltAus: const {'abw2', 'st1'},
        minuten: const {'abw5': 300, 'st3': 300},
      )!;
      expect(elf.reihen.map((r) => r.length).toList(), [1, 4, 4, 2]);
    });
  });

  group('faelltAusFuer', () {
    test('nur Ausfälle dieses Vereins zählen', () {
      final ausfaelle = {
        'abw2': const PlayerAbsence(playerId: 'abw2', gesperrt: false),
        'fremd': const PlayerAbsence(playerId: 'fremd', gesperrt: true),
      };
      expect(faelltAusFuer(ausfaelle, _kader()), {'abw2'});
    });
  });
}
