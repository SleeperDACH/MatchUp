import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/vorwaermen.dart';

/// **Ein Ladekreis ersetzt den Inhalt nur, wenn es keinen gibt.**
///
/// Gemeldet: *„Auch bei guter Internetverbindung sind ganz oft Ladescreens.
/// Wenn man auf etwas tippt, soll gleich alles da sein."*
///
/// Zwei Ursachen, und beide haben in diesem Projekt eine Vorgeschichte:
///
/// * **`isLoading` heißt nicht „nichts da".** Riverpod meldet es auch beim
///   **Nachladen** — und dann hält der Zustand den vorherigen Wert. Sechs
///   Schirme fragten trotzdem danach und tauschten ihre Tabelle gegen einen
///   Kreis: bei jedem Wiederverbinden des Mitgliederstroms, bei jedem
///   Auffrischen der Live-Punkte, bei jeder Rückkehr aus dem Hintergrund.
///   `.when(loading:)` hat das Problem nicht — es überspringt den Ladefall,
///   wenn ein Wert vorliegt (`skipLoadingOnRefresh`, Standard).
/// * **Geladen wurde erst beim Hinsehen.** Dagegen steht [Vorwaermer].
///
/// Der Wächter unten prüft die **Eigenschaft**, nicht einzelne Stellen: kein
/// Ladekreis direkt hinter einer `isLoading`-Frage. Dieselbe Bauart wie
/// `knopfnamen_test` und `kartenkanten_test` — es ist das einzige Mittel, das
/// so eine Regel über Monate hält.

/// Stellen, an denen `isLoading` **richtig** ist: Sie zeigen einen dünnen
/// Balken **über** vorhandenem Inhalt oder entscheiden über die Bereitschaft
/// des Startbildschirms — sie ersetzen nichts.
const _erlaubt = <String>{
  // Der Startschirm wartet ausdrücklich, bis geladen ist.
  'lib/app/widgets/matchup_splash.dart',
  // `anyLoading` entscheidet erst, wenn die Liste leer ist — also wirklich
  // nichts dasteht.
  'lib/features/favorites/ui/favorites_tab.dart',
};

void main() {
  test('kein Ladekreis über vorhandenen Daten', () {
    final treffer = <String>[];
    for (final datei in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      if (_erlaubt.contains(datei.path)) continue;
      final zeilen = datei.readAsLinesSync();
      for (var i = 0; i < zeilen.length; i++) {
        if (!zeilen[i].contains('CircularProgressIndicator')) continue;
        // Die Bedingung steht unmittelbar davor — fünf Zeilen decken auch
        // eine über mehrere Zeilen umbrochene Oder-Verknüpfung ab.
        final davor = zeilen.sublist((i - 5).clamp(0, i), i).join(' ');
        if (davor.contains('isLoading')) {
          treffer.add('${datei.path}:${i + 1}');
        }
      }
    }
    expect(treffer, isEmpty,
        reason: 'Gefragt ist „liegen Daten vor?" (`valueOrNull == null`), '
            'nicht „lädt gerade etwas?" — sonst fällt der Schirm bei jedem '
            'Nachladen auf einen leeren Kreis zurück:\n${treffer.join('\n')}');
  });

  testWidgets('der Vorwärmer holt einmal, und erst nach dem Aufbau',
      (tester) async {
    // Die Reihenfolge ist der Punkt: Erst steht der Schirm, dann laufen die
    // Abfragen. Ein Dutzend Abrufe im selben Frame verzögerte genau den
    // Aufbau, um den es hier geht.
    final ablauf = <String>[];

    final schirm = StatefulBuilder(
      builder: (context, setState) => Vorwaermer(
        holt: (_) => ablauf.add('geholt'),
        child: Builder(builder: (_) {
          ablauf.add('aufbau');
          return TextButton(
            onPressed: () => setState(() {}),
            child: const Text('neu bauen'),
          );
        }),
      ),
    );

    await tester.pumpWidget(MaterialApp(
      home: ProviderScope(child: Scaffold(body: schirm)),
    ));
    await tester.pump();

    expect(ablauf.first, 'aufbau');
    expect(ablauf.where((e) => e == 'geholt'), hasLength(1));

    // Ein Rebuild darf nicht noch einmal anstoßen: Der Schirm baut sich bei
    // jeder Live-Aktualisierung neu, und jedes Mal zu fragen wäre schlimmer
    // als gar nicht vorzuwärmen.
    await tester.tap(find.text('neu bauen'));
    await tester.pump();
    await tester.pump();
    expect(ablauf.where((e) => e == 'geholt'), hasLength(1));
  });
}
