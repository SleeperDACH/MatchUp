import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/data/live_mit_rueckfall.dart';

/// **Ein Live-Strom, der nicht an seiner Verbindung hängt.**
///
/// Gemeldet: *„In der App habe ich öfter den Fehler ‚Deine Ligen ließen sich
/// nicht laden‘ — RealtimeSubscribeException, Status timedOut."*
///
/// Supabase' `.stream()` holt den ersten Schnappschuss **und** abonniert die
/// Änderungen in einem Zug. Scheitert das Abonnement, wirft der ganze Strom,
/// und die Liste kommt gar nicht — obwohl eine gewöhnliche Abfrage sie
/// jederzeit liefert. Der Fehler betrifft das Zuhören, nicht das Lesen.
void main() {
  test('der Schnappschuss kommt, auch wenn das Abonnement sofort wirft',
      () async {
    final strom = liveMitRueckfall<List<String>>(
      abfrage: () async => ['Liga A', 'Liga B'],
      strom: () => Stream<List<String>>.error(
        StateError('RealtimeSubscribeStatus.timedOut'),
      ),
      ersterAbstand: const Duration(milliseconds: 20),
    );

    final erste = await strom.first;
    expect(erste, ['Liga A', 'Liga B'],
        reason: 'die Liste kommt über die Abfrage, nicht über das Abonnement');
  });

  test('ein Verbindungsfehler über vorhandenen Daten erreicht die Oberfläche '
      'nicht', () async {
    final fehler = <Object>[];
    var versuche = 0;
    final strom = liveMitRueckfall<int>(
      abfrage: () async => 1,
      strom: () {
        versuche++;
        // Erst Daten, dann Abbruch — wie eine wegbrechende Verbindung.
        return () async* {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          yield 2;
          throw StateError('weg');
        }();
      },
      ersterAbstand: const Duration(milliseconds: 10),
      beiFehler: fehler.add,
    );

    final gesehen = <int>[];
    final abo = strom.listen(gesehen.add, onError: (Object e) => fail('$e'));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    await abo.cancel();

    expect(gesehen, contains(1), reason: 'der Schnappschuss');
    expect(gesehen, contains(2), reason: 'die Live-Ausgabe');
    expect(fehler, isNotEmpty, reason: 'gemeldet wird er trotzdem — nach innen');
    expect(versuche, greaterThan(1), reason: 'und er verbindet sich neu');
  });

  test('scheitern beide, gibt es einen Fehler — dann ist wirklich nichts da',
      () async {
    final strom = liveMitRueckfall<int>(
      abfrage: () async => throw StateError('offline'),
      strom: () => Stream<int>.error(StateError('timedOut')),
      ersterAbstand: const Duration(milliseconds: 10),
    );
    await expectLater(strom, emitsError(isA<StateError>()));
  });

  test('das Abonnement wird beim Abbestellen wirklich beendet', () async {
    var offen = 0;
    final strom = liveMitRueckfall<int>(
      abfrage: () async => 1,
      strom: () {
        offen++;
        final c = StreamController<int>();
        c.onCancel = () => offen--;
        return c.stream;
      },
      ersterAbstand: const Duration(milliseconds: 10),
    );
    final abo = strom.listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await abo.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(offen, 0, reason: 'sonst bliebe je Schirmwechsel eine Verbindung übrig');
  });
}
