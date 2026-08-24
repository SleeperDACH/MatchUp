import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/auth/username_vorschlag.dart';

/// Wer sich mit Google oder Apple anmeldet, durchläuft die Registrierung nie
/// — und wählt damit auch nie einen Nutzernamen. Der muss abgeleitet werden,
/// und zwar so, dass die Tabelle ihn annimmt: 3–24 Zeichen, eindeutig. Diese
/// Tests halten die Kanten fest, an denen das schiefgeht.
void main() {
  group('Vorschlag', () {
    test('nimmt, was der Anbieter gerade liefert — vor allem anderen', () {
      expect(
        nutzernameVorschlag(
          bevorzugt: 'Felix Sohrmann',
          metadaten: const {'full_name': 'Aus den Metadaten'},
          email: 'felix@example.com',
        ),
        'Felix Sohrmann',
      );
    });

    test('fällt auf die Metadaten zurück', () {
      expect(
        nutzernameVorschlag(
          metadaten: const {'full_name': 'Erika Mustermann'},
          email: 'erika@example.com',
        ),
        'Erika Mustermann',
      );
    });

    test('fällt auf den Teil vor dem @ zurück', () {
      expect(nutzernameVorschlag(email: 'tippkoenig@example.com'),
          'tippkoenig');
    });

    // Apple gibt bei „E-Mail verbergen" eine Wegwerfadresse und keinen Namen.
    // Übrig bleibt die Kennung davor — hässlich, aber gültig und eindeutig.
    test('kommt mit Apples verborgener E-Mail zurecht', () {
      final name =
          nutzernameVorschlag(email: 'ab12cd34ef@privaterelay.appleid.com');
      expect(name, 'ab12cd34ef');
      expect(name.length, lessThanOrEqualTo(maxNutzernameLaenge));
    });

    test('greift zum Platzhalter, wenn gar nichts brauchbar ist', () {
      expect(nutzernameVorschlag(), 'Tipper');
      expect(nutzernameVorschlag(bevorzugt: '  ', email: 'a@b.de'), 'Tipper');
    });

    // „Bo" ist ein echter Vorname und trotzdem zu kurz für die Tabelle —
    // dann muss der nächste Kandidat greifen, nicht der Platzhalter.
    test('überspringt zu kurze Kandidaten statt aufzugeben', () {
      expect(
        nutzernameVorschlag(bevorzugt: 'Bo', email: 'bosse@example.com'),
        'bosse',
      );
    });
  });

  group('Kürzen', () {
    test('zieht Leerraum zusammen', () {
      expect(nutzernameKuerzen('  Felix   Sohrmann  '), 'Felix Sohrmann');
    });

    test('kappt auf 24 Zeichen', () {
      final lang = nutzernameKuerzen('Maximilian Alexander von Habsburg')!;
      expect(lang.length, lessThanOrEqualTo(maxNutzernameLaenge));
      expect(lang, 'Maximilian Alexander von');
    });

    // Fällt die Grenze auf ein Leerzeichen, stünde am Ende ein unsichtbarer
    // Rest — und zwei Namen, die sich nur darin unterscheiden, sähen gleich aus.
    test('lässt kein Leerzeichen am Ende stehen', () {
      final name = nutzernameKuerzen('Alexanderplatzbewohner X')!;
      expect(name, isNot(endsWith(' ')));
      expect(name.length, lessThanOrEqualTo(maxNutzernameLaenge));
    });

    test('meldet null bei zu kurz', () {
      expect(nutzernameKuerzen('Bo'), isNull);
      expect(nutzernameKuerzen(''), isNull);
      expect(nutzernameKuerzen(null), isNull);
    });
  });

  group('Anhang bei Namensgleichheit', () {
    test('hängt die Nummer an, solange Platz ist', () {
      expect(nutzernameMitAnhang('Felix', '2'), 'Felix2');
    });

    // Der entscheidende Fall: Ist der Name schon 24 Zeichen lang, darf die
    // Nummer ihn nicht auf 25 schieben — sonst scheitert genau der Versuch,
    // der die Kollision auflösen sollte.
    test('kürzt die Basis, statt die Grenze zu reißen', () {
      const basis = 'Maximilian Alexander von'; // exakt 24
      expect(basis.length, maxNutzernameLaenge);
      final zweiter = nutzernameMitAnhang(basis, '2');
      expect(zweiter.length, lessThanOrEqualTo(maxNutzernameLaenge));
      expect(zweiter, endsWith('2'));
      expect(zweiter, isNot(basis));
    });

    test('trägt auch eine sechsstellige Kennung', () {
      final name = nutzernameMitAnhang('Maximilian Alexander von', 'a1b2c3');
      expect(name.length, lessThanOrEqualTo(maxNutzernameLaenge));
      expect(name, endsWith('a1b2c3'));
    });

    test('lässt kein Leerzeichen vor dem Anhang stehen', () {
      final name = nutzernameMitAnhang('Michael Müller Junior XY', '2');
      expect(name, isNot(contains(' 2')));
    });
  });
}
