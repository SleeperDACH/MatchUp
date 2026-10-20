import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/logic/round_robin.dart';
import 'package:matchup/features/fantasy/logic/saisonverlauf.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/ui/remis_grenze_editor.dart';

/// Unentschieden bei knappem Ausgang (Ligaeinstellung, 16.10.2026).
void main() {
  group('duellErgebnis', () {
    test('ohne Grenze nur bei Gleichheit', () {
      expect(duellErgebnis(100, 100), 0);
      expect(duellErgebnis(100.1, 100), 1);
      expect(duellErgebnis(99.9, 100), -1);
    });

    test('genau 5,0 ist noch Unentschieden, 5,1 nicht', () {
      expect(duellErgebnis(105, 100, remisGrenze: 5), 0);
      expect(duellErgebnis(100, 105, remisGrenze: 5), 0);
      expect(duellErgebnis(105.1, 100, remisGrenze: 5), 1);
      expect(duellErgebnis(100, 105.1, remisGrenze: 5), -1);
    });

    test('Fließkomma kippt die Grenze nicht', () {
      // 0,1 + 0,2 + … als Summe von Zehnteln — 104,99999 statt 105.
      var summe = 100.0;
      for (var i = 0; i < 50; i++) {
        summe += 0.1;
      }
      expect(duellErgebnis(summe, 100, remisGrenze: 5), 0);
    });
  });

  test('die Tabelle zählt knappe Duelle als Unentschieden', () {
    const ids = ['a', 'b'];
    final gewertet = <int, Map<String, num>>{
      1: {'a': 104, 'b': 100}, // 4 Abstand
      2: {'a': 120, 'b': 100}, // 20 Abstand
    };
    final ohne = h2hStandings(ids, gewertet);
    final a0 = ohne.firstWhere((r) => r.managerId == 'a');
    expect([a0.wins, a0.ties, a0.losses], [2, 0, 0]);

    final mit = h2hStandings(ids, gewertet, remisGrenze: 5);
    final a5 = mit.firstWhere((r) => r.managerId == 'a');
    final b5 = mit.firstWhere((r) => r.managerId == 'b');
    expect([a5.wins, a5.ties, a5.losses], [1, 1, 0]);
    expect([b5.wins, b5.ties, b5.losses], [0, 1, 1]);
  });

  test('Saisonverlauf und Tabelle meinen mit Grenze dasselbe', () {
    const ids = ['a', 'b', 'c', 'd'];
    final gewertet = <int, Map<String, num>>{
      1: {'a': 100, 'b': 97, 'c': 80, 'd': 90},
      2: {'a': 70, 'b': 74, 'c': 60, 'd': 50},
      3: {'a': 75, 'b': 76, 'c': 90, 'd': 75},
    };
    for (final id in ids) {
      final verlauf = saisonverlauf(
          ids: ids,
          managerId: id,
          gewertet: gewertet,
          letzteRunde: 3,
          remisGrenze: 5);
      final rec = h2hStandings(ids, gewertet, remisGrenze: 5)
          .firstWhere((r) => r.managerId == id);
      int zaehle(DuellAusgang a) =>
          verlauf.where((s) => s.ausgang == a).length;
      expect(zaehle(DuellAusgang.sieg), rec.wins, reason: id);
      expect(zaehle(DuellAusgang.unentschieden), rec.ties, reason: id);
      expect(zaehle(DuellAusgang.niederlage), rec.losses, reason: id);
    }
  });

  test('bestehende Ligen ohne Wert bleiben aus', () {
    Map<String, dynamic> zeile(Object? grenze) => {
          'id': 'l1',
          'name': 'Liga',
          'mode': 'liga',
          'season': 2026,
          'draft_pick_seconds': 60,
          'invite_code': 'X',
          'draft_status': 'done',
          'created_by': 'm0',
          'remis_grenze': grenze,
        };
    expect(FantasyLeague.fromJson(zeile(null)).remisGrenze, isNull);
    expect(FantasyLeague.fromJson(zeile(5)).remisGrenze, 5.0);
    expect(FantasyLeague.fromJson(zeile(12.0)).remisGrenze, 12.0);
  });

  test('Ein alter Wert wird auf den nächsten erlaubten gezogen', () {
    expect(RemisGrenzeEditor.erlaubt(3), 5);
    expect(RemisGrenzeEditor.erlaubt(12), 10);
    expect(RemisGrenzeEditor.erlaubt(13), 15);
    expect(RemisGrenzeEditor.erlaubt(80), 50);
  });

  testWidgets('Editor: einschalten setzt 10, Schritte zu fünf, 5 bis 50',
      (tester) async {
    double? wert;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => RemisGrenzeEditor(
            wert: wert,
            onChanged: (v) => setState(() => wert = v),
          ),
        ),
      ),
    ));
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(wert, FantasyLeague.remisGrenzeStandard);
    expect(wert, 10);

    final hoch = find.byTooltip('Abstand für Unentschieden erhöhen');
    final runter = find.byTooltip('Abstand für Unentschieden verringern');
    await tester.tap(hoch);
    await tester.pump();
    expect(wert, 15, reason: 'Fünferschritte');

    // Nach unten bis 5, dann ist Schluss.
    for (var i = 0; i < 5; i++) {
      await tester.tap(runter);
      await tester.pump();
    }
    expect(wert, 5);

    // Nach oben bis 50, dann ist Schluss.
    for (var i = 0; i < 12; i++) {
      await tester.tap(hoch);
      await tester.pump();
    }
    expect(wert, 50);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(wert, isNull, reason: 'ausschalten heißt: nur Punktgleichheit');
  });
}
