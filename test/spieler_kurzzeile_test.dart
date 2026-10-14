import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/logic/naechstes_spiel.dart';
import 'package:matchup/features/fantasy/logic/saisonverlauf.dart';
import 'package:matchup/features/fantasy/logic/spieler_kurzzeile.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

void main() {
  final anpfiff = DateTime(2026, 10, 17, 15, 30);

  group('Spielzeile', () {
    test('vor dem Anpfiff: Gegner und Anstoß', () {
      final z = spielZeile(
        NaechstesSpiel(gegner: '1. FSV Mainz 05', anpfiff: anpfiff, heim: false),
        jetzt: anpfiff.subtract(const Duration(hours: 1)),
      )!;
      expect(z.text, '@ M05');
      expect(z.anstoss, 'Sa 15:30');
      expect(z.laeuft, isFalse);
      expect(z.ausgang, isNull);
    });

    test('läuft ab Anpfiff, auch wenn der Spielplan noch „geplant" sagt', () {
      final z = spielZeile(
        NaechstesSpiel(
            gegner: 'Borussia Dortmund', anpfiff: anpfiff, heim: true),
        jetzt: anpfiff.add(const Duration(minutes: 3)),
      )!;
      expect(z.laeuft, isTrue);
      expect(z.text, '0:0 vs BVB');
    });

    test('beendet: Ausgang aus Sicht seines Vereins', () {
      final z = spielZeile(
        NaechstesSpiel(
          gegner: 'Borussia Dortmund',
          anpfiff: anpfiff,
          heim: false,
          status: FixtureStatus.finished,
          eigeneTore: 2,
          gegnerTore: 1,
        ),
        jetzt: anpfiff.add(const Duration(hours: 3)),
      )!;
      expect(z.text, 'S 2:1 @ BVB');
      expect(z.ausgang, VereinsAusgang.sieg);
    });

    test('spielfrei ergibt keine Zeile', () {
      expect(spielZeile(null, jetzt: anpfiff), isNull);
    });
  });

  group('Statistikzeile', () {
    test('Minuten zuerst, dann was punktet, dann Karten', () {
      expect(
        statistikZeile(
          const PlayerMatchStats(minutes: 90, goals: 2, assists: 1, yellow: 1),
          PlayerPosition.fwd,
        ),
        "90' · 2 Tore · 1 Vorlage · Gelb",
      );
    });

    test('Paraden und zu Null nur, wo sie etwas sagen', () {
      const s = PlayerMatchStats(minutes: 90, saves: 4, cleanSheet: true);
      expect(statistikZeile(s, PlayerPosition.gk), "90' · 4 Paraden · zu Null");
      expect(statistikZeile(s, PlayerPosition.fwd), "90'");
    });

    test('nicht gespielt ergibt keine Zeile', () {
      expect(statistikZeile(null, PlayerPosition.mid), isNull);
      expect(statistikZeile(const PlayerMatchStats(), PlayerPosition.mid),
          isNull);
    });
  });

  test('Serie zählt den letzten Ausgang rückwärts, spielfrei unterbricht nicht',
      () {
    SaisonSpiel s(int r, String? g, double? a, double? b) =>
        SaisonSpiel(runde: r, gegnerId: g, eigene: a, gegner: b);
    final verlauf = [
      s(1, 'x', 50, 60), // N
      s(2, 'x', 70, 60), // S
      s(3, null, null, null), // spielfrei
      s(4, 'x', 80, 60), // S
      s(5, 'x', null, null), // noch offen
    ];
    final r = serie(verlauf)!;
    expect(r.ausgang, DuellAusgang.sieg);
    expect(r.anzahl, 2);
    expect(serie([s(1, 'x', null, null)]), isNull);
  });
}
