import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/app/widgets/team_fixture_list.dart';

/// Mitternacht UTC ist die Platzhalterzeit der Quelle, kein Anstoß.
void main() {
  test('Mitternacht UTC heißt: Zeit noch offen', () {
    expect(anstossOffen(DateTime.utc(2026, 12, 5)), isTrue);
    expect(anstossOffen(DateTime.utc(2026, 12, 5, 14, 30)), isFalse);
    // 01:00 deutscher Winterzeit ist dieselbe Mitternacht UTC.
    expect(anstossOffen(DateTime.utc(2026, 12, 5).toLocal()), isTrue);
  });
}
