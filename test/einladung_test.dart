import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/einladung/einladung.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Link', () {
    test('mit Code und Name', () {
      final link = einladungsLink(code: 'a1b2c3', name: 'BuLi 26/27');
      expect(link.host, 'sleeperdach.github.io');
      expect(link.path, '/MatchUp/einladung/');
      expect(link.queryParameters, {'code': 'a1b2c3', 'name': 'BuLi 26/27'});
    });

    test('ohne Code ist es die allgemeine Einladung, ohne Fragezeichen', () {
      expect(einladungsLink().toString(), einladungsSeite);
    });
  });

  group('Text', () {
    test('trägt Link und Code für alle, die erst installieren', () {
      final t = einladungsText(code: 'a1b2c3', name: 'Büroliga', art: 'Tipprunde');
      expect(t, contains('„Büroliga“'));
      expect(t, contains(einladungsSeite));
      expect(t, contains('Einladungscode a1b2c3'));
    });

    test('allgemein ohne Code', () {
      final t = einladungsText();
      expect(t, contains(einladungsSeite));
      expect(t, isNot(contains('Einladungscode')));
    });
  });

  group('Eingehender Link', () {
    test('App-Schema, wie die Einladungsseite die App öffnet', () {
      expect(
          einladungsCodeAus(Uri.parse(
              'app.matchup.mobile://einladung?code=a1b2c3&name=Liga')),
          'a1b2c3');
    });

    test('die Web-Adresse selbst', () {
      expect(einladungsCodeAus(einladungsLink(code: 'xyz')), 'xyz');
    });

    test('der Passwort-Link ist keine Einladung', () {
      expect(
          einladungsCodeAus(Uri.parse(
              'app.matchup.mobile://login-callback/#access_token=x&type=recovery')),
          isNull);
    });

    test('ohne Code keine Einladung', () {
      expect(einladungsCodeAus(Uri.parse('app.matchup.mobile://einladung')),
          isNull);
      expect(einladungsCodeAus(einladungsLink()), isNull);
    });

    test('merkt Code und Name für die App-Hülle', () {
      offeneEinladung.value = null;
      einladungAusLink(
          Uri.parse('app.matchup.mobile://einladung?code=k1&name=Probe'));
      expect(offeneEinladung.value, (code: 'k1', name: 'Probe'));
      offeneEinladung.value = null;
    });
  });

  group('Startlink', () {
    test('fragt nur beim ersten Start, nicht bei jedem Neustart', () async {
      SharedPreferences.setMockInitialValues({});
      final link = Uri.parse('app.matchup.mobile://einladung?code=s1');

      offeneEinladung.value = null;
      await einladungAusStartLink(link);
      expect(offeneEinladung.value?.code, 's1');

      // Neustart mit demselben Startlink (Hot Restart, Prozess neu).
      offeneEinladung.value = null;
      await einladungAusStartLink(link);
      expect(offeneEinladung.value, isNull);

      // Die Wiederholung im Linkstrom fragt auch nicht.
      einladungAusLink(link);
      expect(offeneEinladung.value, isNull);

      // Derselbe Link später noch einmal angetippt: fragt.
      einladungAusLink(link);
      expect(offeneEinladung.value?.code, 's1');
      offeneEinladung.value = null;
    });

    test('ein neuer Startlink fragt wieder', () async {
      SharedPreferences.setMockInitialValues(
          {'einladung_startlink': 'app.matchup.mobile://einladung?code=alt'});
      offeneEinladung.value = null;
      await einladungAusStartLink(
          Uri.parse('app.matchup.mobile://einladung?code=neu'));
      expect(offeneEinladung.value?.code, 'neu');
      offeneEinladung.value = null;
    });
  });
}
