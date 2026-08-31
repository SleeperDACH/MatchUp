import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/kader_am.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/models/roster_move.dart';

/// **Der Rückblick rechnet mit dem Kader von damals.**
///
/// Gemeldet: „SFV03 hatte keine 230 Punkte auf der Bank." Der Rückblick nahm
/// den **heutigen** Kader — wer nach dem Spieltag geholt wurde, stand darin,
/// und seine Punkte aus jenem Spieltag landeten auf der Bank des neuen
/// Besitzers.
RosterEntry _r(String mgr, String pid) =>
    RosterEntry(managerId: mgr, playerId: pid, acquiredVia: 'draft');

RosterMove _b(String mgr, String pid, bool zugang, DateTime wann) => RosterMove(
      id: wann.millisecondsSinceEpoch,
      leagueId: 'l1',
      managerId: mgr,
      playerId: pid,
      zugang: zugang,
      passiertAm: wann,
    );

Set<String> _ids(List<RosterEntry> k) =>
    {for (final r in k) '${r.managerId}|${r.playerId}'};

void main() {
  final abpfiff = DateTime(2026, 8, 30, 19, 30);
  final danach = DateTime(2026, 8, 31, 15);
  final davor = DateTime(2026, 8, 28, 10);

  test('ohne Bewegungen bleibt es der heutige Kader', () {
    final k = kaderAm(
      aktuell: [_r('a', 'p1'), _r('a', 'p2')],
      bewegungen: const [],
      stichtag: abpfiff,
    );
    expect(_ids(k), {'a|p1', 'a|p2'});
  });

  test('ein Zugang nach dem Abpfiff zählt nicht mehr mit', () {
    // **Der gemeldete Fall.** p3 kam Montag, der Spieltag war Sonntag vorbei.
    final k = kaderAm(
      aktuell: [_r('a', 'p1'), _r('a', 'p3')],
      bewegungen: [_b('a', 'p3', true, danach)],
      stichtag: abpfiff,
    );
    expect(_ids(k), {'a|p1'});
  });

  test('ein Abgang nach dem Abpfiff zählt wieder mit', () {
    // Wer Montag abgegeben wurde, stand am Sonntag noch im Kader — und seine
    // Punkte gehören in diesen Rückblick.
    final k = kaderAm(
      aktuell: [_r('a', 'p1')],
      bewegungen: [_b('a', 'p2', false, danach)],
      stichtag: abpfiff,
    );
    expect(_ids(k), {'a|p1', 'a|p2'});
  });

  test('Bewegungen vor dem Abpfiff bleiben unangetastet', () {
    final k = kaderAm(
      aktuell: [_r('a', 'p1'), _r('a', 'p2')],
      bewegungen: [_b('a', 'p2', true, davor)],
      stichtag: abpfiff,
    );
    expect(_ids(k), {'a|p1', 'a|p2'},
        reason: 'Er kam vor dem Spieltag und stand am Spieltag im Kader');
  });

  test('ein Trade nach dem Abpfiff dreht beide Seiten zurück', () {
    // Ein Trade ist für den einen ein Abgang und für den anderen ein Zugang,
    // beide zur selben Zeit. Deshalb ist der Schlüssel Manager **und**
    // Spieler, nicht der Spieler allein.
    final k = kaderAm(
      aktuell: [_r('b', 'p1'), _r('a', 'p2')],
      bewegungen: [
        _b('a', 'p1', false, danach),
        _b('b', 'p1', true, danach),
        _b('b', 'p2', false, danach),
        _b('a', 'p2', true, danach),
      ],
      stichtag: abpfiff,
    );
    expect(_ids(k), {'a|p1', 'b|p2'}, reason: 'Der Stand vor dem Tausch');
  });

  group('abpfiffDerRunde', () {
    test('letzter Anpfiff plus zwei Stunden', () {
      final a = [
        DateTime(2026, 8, 28, 20, 30),
        DateTime(2026, 8, 30, 17, 30),
        DateTime(2026, 8, 29, 15, 30),
      ];
      expect(abpfiffDerRunde(a), DateTime(2026, 8, 30, 19, 30));
    });

    test('ohne Spiele gibt es keinen Abpfiff', () {
      expect(abpfiffDerRunde(const []), isNull);
    });
  });
}
