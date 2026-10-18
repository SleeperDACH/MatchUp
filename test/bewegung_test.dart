import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/widgets/aufleuchten.dart';
import 'package:matchup/app/widgets/skelett.dart';

/// Bewegung und Laden (Design-Ideen Punkte 6 und 7, 15.10.2026).
void main() {
  Widget rahmen(Widget kind) =>
      MaterialApp(home: Scaffold(body: Center(child: kind)));

  /// Zählt die Leucht-Flächen: Ohne Aufleuchten steht nur das Kind da.
  int leuchten(WidgetTester tester) => tester
      .widgetList<DecoratedBox>(find.descendant(
          of: find.byType(Aufleuchten), matching: find.byType(DecoratedBox)))
      .length;

  testWidgets('Aufleuchten nur, wenn der Zähler steigt', (tester) async {
    Widget mit(int z) => rahmen(
        Aufleuchten(zaehler: z, child: const SizedBox(width: 50, height: 50)));

    await tester.pumpWidget(mit(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(leuchten(tester), 0, reason: 'nie beim ersten Aufbau');

    await tester.pumpWidget(mit(2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(leuchten(tester), 1, reason: 'ein Tor leuchtet auf');

    await tester.pump(const Duration(seconds: 1));
    expect(leuchten(tester), 0, reason: 'und hört wieder auf');

    await tester.pumpWidget(mit(1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(leuchten(tester), 0, reason: 'ein korrigiertes Tor ist kein Ereignis');
  });

  testWidgets('das Skelett passt in jeden Platz', (tester) async {
    // Begrenzte Höhe: so viele Zeilen, wie hineinpassen — kein Überlauf.
    await tester.pumpWidget(rahmen(const SizedBox(height: 90, child: Skelett())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    // Unbegrenzt in einer Spalte: die vorgegebene Zahl.
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Column(children: const [Skelett(zeilen: 4)])))));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });
}
