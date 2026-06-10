import 'package:flutter_test/flutter_test.dart';
import 'package:meine_app/core/models/models.dart';

void main() {
  group('LeagueInfo.seasonFor', () {
    test('Vereinsliga: Saisonwechsel im Juli', () {
      expect(Leagues.bundesliga.seasonFor(DateTime(2026, 6, 10)), 2025);
      expect(Leagues.bundesliga.seasonFor(DateTime(2026, 7, 1)), 2026);
      expect(Leagues.bundesliga.seasonFor(DateTime(2027, 2, 1)), 2026);
    });

    test('Turnier: festes Jahr unabhängig vom Datum', () {
      expect(Leagues.wm2026.seasonFor(DateTime(2026, 6, 10)), 2026);
      expect(Leagues.wm2026.seasonFor(DateTime(2026, 7, 20)), 2026);
    });
  });

  group('Leagues.byId', () {
    test('findet Wettbewerbe und fällt auf Bundesliga zurück', () {
      expect(Leagues.byId('wm2026'), Leagues.wm2026);
      expect(Leagues.byId('bundesliga'), Leagues.bundesliga);
      expect(Leagues.byId('unbekannt'), Leagues.bundesliga);
    });
  });
}
