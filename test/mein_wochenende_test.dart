import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/core/models/team_fixture.dart';
import 'package:matchup/features/favorites/logic/next_favorite_fixtures.dart';

/// **Die Fußballwoche endet Montag um 15:00.**
///
/// Gewünscht: *„Statt einem Spiel an dem Tag den Bereich umbauen in ‚Mein
/// Wochenende' und alle Spiele meiner Favoriten von Freitag bis einschließlich
/// Montag anzeigen … Auch da gilt: Montag, 15:00 Uhr."*
///
/// Es ist derselbe Schnitt, an dem in dieser App die Waiver-Anträge vergeben
/// werden und der Fantasy-Spieltag wechselt. Der Montag ist das Scharnier, und
/// er ist die einzige Kante, an der man sich vertun kann: vormittags gehört er
/// noch zum vergangenen Wochenende, nachmittags schon zum kommenden.

TeamFixture _f(String heim, DateTime anstoss, {int? tore}) => TeamFixture(
      id: 'sportmonks:$heim${anstoss.day}${anstoss.hour}',
      kickoff: anstoss,
      status: tore == null ? FixtureStatus.scheduled : FixtureStatus.finished,
      leagueName: 'Bundesliga',
      round: 3,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: const TeamRef(id: 'gast', name: 'FC Gast', shortName: 'GAS'),
      homeScore: tore,
      awayScore: tore == null ? null : 0,
    );

void main() {
  group('fussballWoche', () {
    test('am Samstag gilt das laufende Wochenende', () {
      final w = fussballWoche(DateTime(2026, 9, 12, 18));
      expect(w.von, DateTime(2026, 9, 11)); // Freitag 00:00
      expect(w.bis, DateTime(2026, 9, 14, 15)); // Montag 15:00
    });

    test('Montagvormittag gehört noch zum vergangenen Wochenende', () {
      final w = fussballWoche(DateTime(2026, 9, 14, 10));
      expect(w.von, DateTime(2026, 9, 11));
      expect(w.bis, DateTime(2026, 9, 14, 15));
    });

    test('Montagnachmittag springt auf das kommende', () {
      // **Die Kante.** Um 15:01 ist die Woche vorbei, und der Homescreen zeigt
      // ab dann den nächsten Spieltag.
      final w = fussballWoche(DateTime(2026, 9, 14, 15, 1));
      expect(w.von, DateTime(2026, 9, 18));
      expect(w.bis, DateTime(2026, 9, 21, 15));
    });

    test('genau 15:00 zählt noch zum alten Fenster', () {
      // Das Fenster ist bis 15:00 **offen**; erst danach kippt es.
      final w = fussballWoche(DateTime(2026, 9, 14, 15));
      expect(w.bis, DateTime(2026, 9, 21, 15));
    });

    test('mitten in der Woche steht das kommende Wochenende', () {
      final w = fussballWoche(DateTime(2026, 9, 16, 9));
      expect(w.von, DateTime(2026, 9, 18));
      expect(w.bis, DateTime(2026, 9, 21, 15));
    });
  });

  group('wochenendSpiele', () {
    final samstag = DateTime(2026, 9, 12, 18);

    test('Freitag bis Montag, gespielte Partien eingeschlossen', () {
      // Genau der Punkt: Das Freitagsspiel ist längst abgepfiffen und bleibt
      // trotzdem stehen. Vorher verschwand es mit dem Schlusspfiff.
      final spiele = wochenendSpiele(
        fixtures: [
          _f('Donnerstag', DateTime(2026, 9, 10, 20, 30)),
          _f('Freitag', DateTime(2026, 9, 11, 20, 30), tore: 2),
          _f('Samstag', DateTime(2026, 9, 12, 15, 30)),
          _f('Sonntag', DateTime(2026, 9, 13, 17, 30)),
          _f('Montag', DateTime(2026, 9, 14, 12)),
          _f('Dienstag', DateTime(2026, 9, 15, 20, 30)),
        ],
        jetzt: samstag,
      );
      expect([for (final f in spiele) f.home.name],
          ['Freitag', 'Samstag', 'Sonntag', 'Montag']);
    });

    test('ein Montagabendspiel fällt heraus', () {
      // Nach 15:00 gehört der Montag schon zur nächsten Woche — und dorthin
      // gehört dann auch die Partie.
      final spiele = wochenendSpiele(
        fixtures: [_f('Montagabend', DateTime(2026, 9, 14, 20, 30))],
        jetzt: samstag,
      );
      expect(spiele, isEmpty);
    });

    test('Favorit gegen Favorit steht einmal da', () {
      final doppelt = _f('Derby', DateTime(2026, 9, 12, 15, 30));
      expect(
        wochenendSpiele(fixtures: [doppelt, doppelt], jetzt: samstag).length,
        1,
      );
    });

    test('nach Anstoß sortiert, damit die Liste den Verlauf liest', () {
      final spiele = wochenendSpiele(
        fixtures: [
          _f('Sonntag', DateTime(2026, 9, 13, 17, 30)),
          _f('Freitag', DateTime(2026, 9, 11, 20, 30)),
          _f('Samstag', DateTime(2026, 9, 12, 15, 30)),
        ],
        jetzt: samstag,
      );
      expect([for (final f in spiele) f.home.name],
          ['Freitag', 'Samstag', 'Sonntag']);
    });

    test('ohne Spiele im Fenster bleibt es leer', () {
      expect(
        wochenendSpiele(
          fixtures: [_f('Weit weg', DateTime(2026, 10, 3, 15, 30))],
          jetzt: samstag,
        ),
        isEmpty,
      );
    });
  });
}
