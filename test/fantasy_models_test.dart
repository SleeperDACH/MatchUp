import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

void main() {
  group('DraftPickTime', () {
    test('alle 11 Stufen vorhanden, Sekunden eindeutig', () {
      expect(DraftPickTime.values.length, 11);
      final seconds = DraftPickTime.values.map((t) => t.seconds).toSet();
      expect(seconds.length, 11);
    });

    test('fromSeconds findet Stufe, sonst Fallback 1 Minute', () {
      expect(DraftPickTime.fromSeconds(300), DraftPickTime.m5);
      expect(DraftPickTime.fromSeconds(86400), DraftPickTime.d1);
      expect(DraftPickTime.fromSeconds(999), DraftPickTime.m1);
    });

    test('Live-Einordnung: bis 10 Minuten live, danach slow', () {
      expect(DraftPickTime.m10.isLive, isTrue);
      expect(DraftPickTime.m30.isLive, isFalse);
      expect(DraftPickTime.d1.isLive, isFalse);
    });
  });

  group('FantasyPlayer Alter / U20', () {
    final cutoff = DateTime(2025, 8, 1); // ~1. Spieltag

    FantasyPlayer player(int birthYear) => FantasyPlayer(
          id: 'x',
          name: 'Test',
          position: PlayerPosition.mid,
          club: 'Test',
          birthDate: DateTime(birthYear, 1, 1),
          nationality: 'de',
        );

    test('Alter zum Stichtag', () {
      expect(player(2005).ageOn(cutoff), 20);
      expect(player(2006).ageOn(cutoff), 19);
    });

    test('U20 = jünger als 20 am Stichtag', () {
      expect(player(2006).isU20On(cutoff), isTrue); // 19
      expect(player(2005).isU20On(cutoff), isFalse); // 20
    });

    test('Geburtstag nach Stichtag zählt noch nicht', () {
      final p = FantasyPlayer(
        id: 'x',
        name: 'Test',
        position: PlayerPosition.fwd,
        club: 'Test',
        birthDate: DateTime(2005, 12, 31),
        nationality: 'de',
      );
      expect(p.ageOn(cutoff), 19);
      expect(p.isU20On(cutoff), isTrue);
    });
  });

  group('isRookieFor (Dynasty U20-Draft-Pool)', () {
    FantasyPlayer player(int birthYear, {bool foreign = false}) => FantasyPlayer(
          id: 'x',
          name: 'T',
          position: PlayerPosition.fwd,
          club: 'C',
          birthDate: DateTime(birthYear, 1, 1),
          nationality: 'de',
          isForeignNewcomer: foreign,
        );

    test('U20 zum 1. Spieltag ist Rookie', () {
      expect(player(2006).isRookieFor(2025), isTrue); // 19 -> U20
      expect(player(2005).isRookieFor(2025), isFalse); // 20 -> etabliert
    });

    test('Auslands-Neuzugang ist Rookie unabhängig vom Alter', () {
      expect(player(1995, foreign: true).isRookieFor(2025), isTrue);
    });

    test('etablierter Inländer ist kein Rookie', () {
      expect(player(1998).isRookieFor(2025), isFalse);
    });
  });

  group('Serialisierung', () {
    test('FantasyScoring JSON round-trip', () {
      final json = FantasyScoring.kickbaseStyle.toJson();
      final back = FantasyScoring.fromJson(json);
      expect(back.goalGk, 6);
      expect(back.redCard, -3);
    });

    test('RosterConfig: Kadergröße = Runden', () {
      const r = RosterConfig();
      expect(r.squadSize, 1 + 4 + 4 + 2 + 5);
      expect(r.starters, 11);
    });

    test('FantasyMode fromId Fallback', () {
      expect(FantasyMode.fromId('dynasty'), FantasyMode.dynasty);
      expect(FantasyMode.fromId('quatsch'), FantasyMode.liga);
    });
  });
}
