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

  group('Waiver', () {
    test('WaiverStatus fromId mit Fallback auf pending', () {
      expect(WaiverStatus.fromId('won'), WaiverStatus.won);
      expect(WaiverStatus.fromId('cancelled'), WaiverStatus.cancelled);
      expect(WaiverStatus.fromId('unbekannt'), WaiverStatus.pending);
      expect(WaiverStatus.pending.isPending, isTrue);
      expect(WaiverStatus.won.isPending, isFalse);
    });

    test('WaiverClaim.fromJson liest alle Felder', () {
      final c = WaiverClaim.fromJson({
        'id': 'c1',
        'league_id': 'l1',
        'manager_id': 'm1',
        'add_player_id': 'seed:5',
        'drop_player_id': 'seed:9',
        'rank': 2,
        'status': 'won',
        'reason': null,
        'created_at': '2026-06-11T10:00:00Z',
      });
      expect(c.addPlayerId, 'seed:5');
      expect(c.dropPlayerId, 'seed:9');
      expect(c.rank, 2);
      expect(c.status, WaiverStatus.won);
    });

    test('WaiverClaim.fromJson: Defaults ohne drop/rank/status', () {
      final c = WaiverClaim.fromJson({
        'id': 'c2',
        'league_id': 'l1',
        'manager_id': 'm1',
        'add_player_id': 'seed:1',
        'created_at': '2026-06-11T10:00:00Z',
      });
      expect(c.dropPlayerId, isNull);
      expect(c.rank, 1);
      expect(c.status, WaiverStatus.pending);
    });

    test('FantasyManager.fromJson liest waiver_priority', () {
      final m = FantasyManager.fromJson({
        'user_id': 'u1',
        'draft_position': 3,
        'waiver_priority': 5,
        'profiles': {'username': 'Felix'},
      });
      expect(m.waiverPriority, 5);
      expect(m.username, 'Felix');
    });
  });

  group('roundsThisPhase (Kadergröße wird nie überschritten)', () {
    FantasyLeague league(FantasyMode mode, DraftPhase phase) => FantasyLeague(
          id: 'l',
          name: 'L',
          mode: mode,
          season: 2025,
          pickTime: DraftPickTime.m1,
          scoring: FantasyScoring.kickbaseStyle,
          roster: const RosterConfig(), // squad 16
          inviteCode: 'x',
          draftStatus: DraftStatus.drafting,
          createdBy: 'u',
          draftPhase: phase,
          u20Rounds: 3,
        );

    test('Liga: Haupt-Draft füllt den ganzen Kader', () {
      expect(league(FantasyMode.liga, DraftPhase.startup).roundsThisPhase, 16);
    });

    test('Dynasty: Haupt-Draft lässt Platz für U20-Runden', () {
      expect(league(FantasyMode.dynasty, DraftPhase.startup).roundsThisPhase,
          16 - 3);
      expect(league(FantasyMode.dynasty, DraftPhase.u20).roundsThisPhase, 3);
    });
  });
}
