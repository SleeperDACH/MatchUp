import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/features/fantasy/data/fantasy_league_repository.dart';
import 'package:meine_app/features/fantasy/models/fantasy_models.dart';

WaiverClaim _claim(String id, {String status = 'pending'}) => WaiverClaim.fromJson({
      'id': id,
      'league_id': 'lg',
      'manager_id': 'mgr',
      'add_player_id': 'seed:1',
      'status': status,
      'created_at': '2026-07-01T12:00:00Z',
    });

void main() {
  group('dedupWaiverClaimsById', () {
    test('entfernt doppelt gelieferte Anträge (gleiche id)', () {
      final result = dedupWaiverClaimsById([
        _claim('a'),
        _claim('a'), // Realtime-Duplikat
        _claim('b'),
      ]);
      expect(result.map((c) => c.id).toList(), ['a', 'b']);
    });

    test('behält bei Duplikaten den zuletzt gelieferten Stand', () {
      final result = dedupWaiverClaimsById([
        _claim('a', status: 'pending'),
        _claim('a', status: 'cancelled'),
      ]);
      expect(result, hasLength(1));
      expect(result.single.status, WaiverStatus.cancelled);
    });

    test('lässt eindeutige Anträge in Reihenfolge unverändert', () {
      final result = dedupWaiverClaimsById([_claim('a'), _claim('b'), _claim('c')]);
      expect(result.map((c) => c.id).toList(), ['a', 'b', 'c']);
    });
  });
}
