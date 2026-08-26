import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/home_screen.dart';
import 'package:matchup/app/theme.dart';

/// Was der Homescreen **ansagt** und wie groß seine Tastflächen sind — beides
/// sieht man einem Screenshot nicht an, und beides ging bisher unter.
///
/// Die Kartenreihen selbst hängen an Riverpod-Providern und lassen sich ohne
/// halben Homescreen nicht rendern (siehe `karten_layout_preview_test.dart`);
/// geprüft wird deshalb, was ohne sie zu haben ist: der gemeinsame
/// Abschnittskopf und die Maßfunktion, aus der die Kartenhöhen kommen.

Widget _rahmen(Widget kind,
        {double schrift = 1.0, TargetPlatform platform = TargetPlatform.iOS}) =>
    MaterialApp(
      theme: buildAppTheme().copyWith(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(schrift)),
        child: Scaffold(body: kind),
      ),
    );

void main() {
  testWidgets('Kopf zeigt Versalien, sagt aber die Normalschreibung an',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
        _rahmen(Builder(builder: (c) => abschnittsKopf(c, 'News'))));

    // Im Bild Versalien — vorgelesen buchstabieren VoiceOver und TalkBack
    // „NEWS" sonst als N-E-W-S.
    expect(find.text('NEWS'), findsOneWidget);
    final knoten = tester.getSemantics(find.bySemanticsLabel('News'));
    expect(knoten.flagsCollection.isHeader, isTrue,
        reason: 'Als Überschrift ausgezeichnet, damit man abschnittsweise '
            'springen kann');
    handle.dispose();
  });

  testWidgets('Der Zähler gehört zur Überschrift, nicht daneben',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_rahmen(
        Builder(builder: (c) => abschnittsKopf(c, 'Meine Ligen', count: 4))));

    // Eine Ansage statt zweier — „4" allein sagte nicht, wovon es vier zählt.
    expect(find.bySemanticsLabel('Meine Ligen, 4'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('„Alle ›" ist ein Knopf mit tastbarer Fläche', (tester) async {
    final handle = tester.ensureSemantics();
    var getippt = 0;
    await tester.pumpWidget(_rahmen(Builder(
        builder: (c) =>
            abschnittsKopf(c, 'News', onMore: () => getippt++))));

    // 44 auf iOS — nicht die 24 aus WCAG 2.2, die gelten für Web.
    final flaeche = tester.getSize(find.byType(InkWell));
    expect(flaeche.height, greaterThanOrEqualTo(44));
    expect(flaeche.width, greaterThanOrEqualTo(44));

    // Vorgelesen ein Knopf mit Namen — vorher nur der Text „Alle ›", also
    // „Alle, geschlossenes Anführungszeichen".
    final knoten = tester.getSemantics(find.bySemanticsLabel('Alle anzeigen'));
    expect(knoten.flagsCollection.isButton, isTrue);

    await tester.tap(find.byType(InkWell));
    expect(getippt, 1);
    handle.dispose();
  });

  testWidgets('Android bekommt 48, nicht Apples 44', (tester) async {
    // Die beiden Richtlinien nennen verschiedene Maße; eine gemeinsame Zahl
    // für beide Plattformen ist genau der Fehler, den sie benennen.
    await tester.pumpWidget(_rahmen(
        Builder(builder: (c) => abschnittsKopf(c, 'News', onMore: () {})),
        platform: TargetPlatform.android));

    expect(tester.getSize(find.byType(InkWell)).height,
        greaterThanOrEqualTo(48));
  });

  testWidgets('Der Kopf bricht bei größter Systemschrift um, statt zu laufen',
      (tester) async {
    // Gefunden im Simulator bei „accessibility-extra-extra-extra-large":
    // „MEINE VEREINE" und das Datum passten nicht mehr nebeneinander, die
    // Zeile lief 67 Punkte über den rechten Rand.
    await tester.pumpWidget(_rahmen(
        Builder(
            builder: (c) => abschnittsKopf(c, 'Meine Vereine',
                zusatz: 'Montag, 24. Aug.')),
        schrift: 3.1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Kartenhöhe wächst mit der Systemschrift — bis zum Deckel',
      (tester) async {
    Future<double> hoeheBei(double schrift) async {
      late double h;
      await tester.pumpWidget(_rahmen(
          Builder(builder: (c) {
            h = kartenHoehe(c, 132);
            return const SizedBox.shrink();
          }),
          schrift: schrift));
      return h;
    }

    expect(await hoeheBei(1.0), closeTo(132, 0.01));
    // Mitwachsen: bei 1,3 braucht ein zweizeiliger Liganame 38 statt 29
    // Punkte — in der festen 132er-Karte lief er unten heraus.
    expect(await hoeheBei(1.3), closeTo(171.6, 0.01));
    // Und der Deckel: vier Karten nebeneinander können nicht breiter werden,
    // also wächst hier auch nichts mehr.
    expect(await hoeheBei(3.0), closeTo(171.6, 0.01));
  });
}
