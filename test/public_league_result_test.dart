import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/leagues/models/public_league_result.dart';

void main() {
  Map<String, dynamic> row({
    String kind = 'fantasy',
    String joinPolicy = 'open',
    bool joinable = true,
    bool isMember = false,
    bool requested = false,
    int memberCount = 4,
    int? maxTeams = 10,
  }) =>
      {
        'kind': kind,
        'id': 'abc',
        'name': 'Test-Liga',
        'season': 2025,
        'member_count': memberCount,
        'join_policy': joinPolicy,
        'joinable': joinable,
        'is_member': isMember,
        'requested': requested,
        'max_teams': maxTeams,
      };

  group('PublicLeagueResult.fromJson', () {
    test('liest Felder und Defaults korrekt', () {
      final r = PublicLeagueResult.fromJson(row());
      expect(r.isFantasy, isTrue);
      expect(r.name, 'Test-Liga');
      expect(r.memberCount, 4);
      expect(r.maxTeams, 10);
      expect(r.joinable, isTrue);
      expect(r.isInviteOnly, isFalse);
    });

    test('fehlende Bool-/Zahlfelder fallen auf Standard zurück', () {
      final r = PublicLeagueResult.fromJson({
        'kind': 'tip',
        'id': 'x',
        'name': 'Runde',
        'season': 2025,
        'join_policy': 'open',
      });
      expect(r.memberCount, 0);
      expect(r.joinable, isFalse);
      expect(r.isMember, isFalse);
      expect(r.requested, isFalse);
      expect(r.maxTeams, isNull);
    });
  });

  group('isFull', () {
    test('Fantasy voll, wenn memberCount das Limit erreicht', () {
      expect(PublicLeagueResult.fromJson(row(memberCount: 10, maxTeams: 10)).isFull,
          isTrue);
      expect(PublicLeagueResult.fromJson(row(memberCount: 9, maxTeams: 10)).isFull,
          isFalse);
    });

    test('ohne Limit (Tipprunde) nie voll', () {
      final r = PublicLeagueResult.fromJson(
          row(kind: 'tip', memberCount: 999, maxTeams: null));
      expect(r.isFull, isFalse);
    });
  });

  test('isInviteOnly erkennt Einladungsmodus', () {
    expect(PublicLeagueResult.fromJson(row(joinPolicy: 'invite')).isInviteOnly,
        isTrue);
  });
}
