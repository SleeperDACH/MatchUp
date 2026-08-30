import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/widgets/leise_reiter.dart';

/// Symbole in der Reiterleiste: **alle oder keiner.**
///
/// Der Anlass war die Liga-Leiste, die an zweiter Stelle das Markenzeichen
/// *anstelle* des Wortes trug — ein unbeschrifteter Reiter zwischen drei
/// beschrifteten. Das las sich nicht als Marke, sondern als Bruch. Ein Golden
/// zeigt das zwar, aber nur, wenn jemand hinsieht; die Zusicherung fängt es
/// beim ersten Aufbau.
Widget leiste(List<String> titel,
        {Map<int, Widget Function(bool, Color)> symbole = const {}}) =>
    MaterialApp(
      home: DefaultTabController(
        length: titel.length,
        child: Scaffold(
          appBar: AppBar(bottom: LeiseReiter(titel: titel, symbole: symbole)),
        ),
      ),
    );

/// Dieselbe Leiste **ohne** `AppBar`. Für den Fehlerfall: In der `AppBar`
/// zieht der gescheiterte Aufbau einen zweiten Fehler nach sich (die
/// Ersatzfläche passt nicht in die reservierte Höhe), und `takeException`
/// fasst mehrere Fehler zu einer nichtssagenden Sammelmeldung zusammen.
Widget losseLeiste(List<String> titel,
        {Map<int, Widget Function(bool, Color)> symbole = const {}}) =>
    MaterialApp(
      home: DefaultTabController(
        length: titel.length,
        child: Scaffold(
          body: Column(children: [LeiseReiter(titel: titel, symbole: symbole)]),
        ),
      ),
    );

Widget punkt(bool aktiv, Color farbe) => Icon(Icons.circle, color: farbe);

void main() {
  const vier = ['Übersicht', 'MatchUp', 'Kader', 'Tabelle'];

  testWidgets('mit Symbolen steht über jedem Wort ein Zeichen', (tester) async {
    await tester.pumpWidget(leiste(vier, symbole: {
      for (var i = 0; i < vier.length; i++) i: punkt,
    }));

    // Jedes Wort steht weiterhin da — das Symbol ersetzt es nicht.
    for (final t in vier) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.byIcon(Icons.circle), findsNWidgets(4));
  });

  testWidgets('eine Leiste mit einem einzelnen Symbol fliegt auf',
      (tester) async {
    // Die rote Ersatzfläche will unendlich hoch werden und löst dabei einen
    // zweiten Fehler aus; `takeException` fasst mehrere zu einer
    // nichtssagenden Sammelmeldung zusammen. Hier ersetzt sie ein Nichts.
    // (Und zwar *im* Test wieder zurückgesetzt, nicht per `addTearDown`: Die
    // Prüfung darauf läuft vor den Aufräumern.)
    final ersatz = ErrorWidget.builder;
    ErrorWidget.builder = (_) => const SizedBox.shrink();
    await tester.pumpWidget(losseLeiste(vier, symbole: {1: punkt}));
    ErrorWidget.builder = ersatz;
    expect(
      tester.takeException().toString(),
      contains('entweder überall oder nirgends'),
    );
  });

  testWidgets('ohne Symbole bleibt die Leiste niedrig', (tester) async {
    await tester.pumpWidget(leiste(vier));
    final ohne = tester
        .widget<LeiseReiter>(find.byType(LeiseReiter))
        .preferredSize
        .height;

    await tester.pumpWidget(leiste(vier, symbole: {
      for (var i = 0; i < vier.length; i++) i: punkt,
    }));
    final mit = tester
        .widget<LeiseReiter>(find.byType(LeiseReiter))
        .preferredSize
        .height;

    expect(mit, greaterThan(ohne));
  });

  testWidgets('die Leiste ist so hoch, wie sie sich ausgibt', (tester) async {
    // Beim Umbau meldete `preferredSize` schon die neue Höhe, während der
    // Aufbau noch die alte Konstante benutzte: Die Leiste lief unten über.
    await tester.pumpWidget(leiste(vier, symbole: {
      for (var i = 0; i < vier.length; i++) i: punkt,
    }));
    expect(tester.takeException(), isNull);

    final leiste_ = tester.widget<LeiseReiter>(find.byType(LeiseReiter));
    expect(
      tester.getSize(find.byType(LeiseReiter)).height,
      leiste_.preferredSize.height,
    );
  });
}
