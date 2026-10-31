import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// Punkt 9 der Nutzer-Analyse: Der Draft wirkte wie ein Termin.
void main() {
  test('langsamer Draft: kein Termin nötig, mit der eingestellten Zeit', () {
    expect(DraftPickTime.h8.ablauf, 'Kein Termin nötig');
    expect(DraftPickTime.h8.ablaufSatz,
        'Kein Termin nötig: Jeder hat 8 Stunden je Pick, sonst wählt die App '
        'automatisch.');
  });

  test('schneller Draft sagt ehrlich, dass alle online sein sollten', () {
    expect(DraftPickTime.m1.ablauf, contains('gleichzeitig'));
    expect(DraftPickTime.m1.ablaufSatz, contains('1 Minute je Pick'));
    expect(DraftPickTime.m1.ablaufSatz, contains('automatisch'));
    // … und nennt den Ausweg: mehr Zeit, kein Termin.
    expect(DraftPickTime.m1.ablaufSatz, contains('bis zu einem Tag'));
  });

  test('kein Fachwort mehr', () {
    for (final t in DraftPickTime.values) {
      expect(t.ablauf, isNot(contains('Draft')));
    }
  });
}
