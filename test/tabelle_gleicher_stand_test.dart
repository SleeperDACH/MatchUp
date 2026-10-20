import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/data/fantasy_stats_source.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_engine.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';
import 'package:matchup/features/fantasy/providers.dart';

/// **Jedes Gerät rechnet dieselbe Tabelle** (gemeldet 19.10.2026: „jedem
/// werden unterschiedliche Tabellen angezeigt in der gleichen Liga").
///
/// Die Tabelle entsteht auf dem Gerät aus Statistik, Spielplan und Pool. Die
/// Statistik wurde einmal je Sitzung geladen; sprang danach ein Spieltag auf
/// „abgepfiffen", zählte die Tabelle ihn mit den Zwischenständen vom Laden —
/// auf jedem Gerät mit anderen. Gehalten wird hier:
///  * ein Spieltag ist auch nach der Uhr durch, nicht nur nach dem Spielplan;
///  * kommt ein abgepfiffener Spieltag dazu, wird die Statistik neu geladen;
///  * sonst nicht (kein Nachladen im 30-Sekunden-Takt des Spielplans).
class _ZaehlendeQuelle implements FantasyStatsSource {
  int geladen = 0;

  @override
  Future<Map<String, PlayerMatchStats>> roundStats({
    required List<FantasyPlayer> pool,
    required int season,
    required int round,
  }) async =>
      const {};

  @override
  Future<Map<int, Map<String, PlayerMatchStats>>> seasonStats({
    required int season,
  }) async {
    geladen++;
    return const {};
  }
}

Fixture _spiel(int runde, DateTime anpfiff, FixtureStatus status) => Fixture(
      id: 'sportmonks:$runde${anpfiff.hour}',
      leagueId: 'bundesliga',
      season: 2026,
      round: runde,
      roundName: '$runde. Spieltag',
      kickoff: anpfiff,
      status: status,
      home: TeamRef(id: 'h$runde', name: 'Heim $runde', shortName: 'H'),
      away: TeamRef(id: 'a$runde', name: 'Gast $runde', shortName: 'G'),
    );

void main() {
  group('rundeDurch', () {
    final anpfiff = DateTime(2026, 10, 18, 17, 30);

    test('beendet nach dem Spielplan', () {
      expect(
          rundeDurch([_spiel(6, anpfiff, FixtureStatus.finished)],
              anpfiff.add(const Duration(minutes: 1))),
          isTrue);
    });

    test('nach der Uhr durch, auch wenn das Gerät noch „läuft" kennt', () {
      final spiele = [_spiel(6, anpfiff, FixtureStatus.live)];
      expect(rundeDurch(spiele, anpfiff.add(const Duration(hours: 2))),
          isFalse);
      expect(
          rundeDurch(spiele, anpfiff.add(const Duration(hours: 3, minutes: 1))),
          isTrue);
    });

    test('ein offenes Spiel hält den Spieltag offen', () {
      final spiele = [
        _spiel(6, anpfiff, FixtureStatus.finished),
        _spiel(6, anpfiff.add(const Duration(days: 1)),
            FixtureStatus.scheduled),
      ];
      expect(rundeDurch(spiele, anpfiff.add(const Duration(hours: 4))),
          isFalse);
    });
  });

  test('Kommt ein abgepfiffener Spieltag dazu, lädt die Statistik neu',
      () async {
    final quelle = _ZaehlendeQuelle();
    final vergangen = DateTime.now().subtract(const Duration(days: 7));
    final laeuft = DateTime.now().subtract(const Duration(minutes: 30));
    var spiele = [
      _spiel(5, vergangen, FixtureStatus.finished),
      _spiel(6, laeuft, FixtureStatus.live),
    ];
    final c = ProviderContainer(overrides: [
      fantasyStatsSourceProvider.overrideWithValue(quelle),
      fantasySeasonFixturesProvider.overrideWith((ref) async => spiele),
    ]);
    addTearDown(c.dispose);
    c.listen(seasonStatsProvider, (_, _) {});

    await c.read(seasonStatsProvider.future);
    expect(quelle.geladen, 1, reason: 'beim Start genau einmal');

    // Der Spielplan wird während des Spieltags nachgeladen, ohne dass ein
    // Spieltag fertig wird: keine neue Statistik.
    c.invalidate(fantasySeasonFixturesProvider);
    await c.read(fantasySeasonFixturesProvider.future);
    await c.read(seasonStatsProvider.future);
    expect(quelle.geladen, 1, reason: 'kein Nachladen ohne neuen Spieltag');

    // Spieltag 6 ist abgepfiffen: Die Statistik muss nachziehen.
    spiele = [
      _spiel(5, vergangen, FixtureStatus.finished),
      _spiel(6, laeuft, FixtureStatus.finished),
    ];
    c.invalidate(fantasySeasonFixturesProvider);
    await c.read(fantasySeasonFixturesProvider.future);
    await c.read(seasonStatsProvider.future);
    expect(quelle.geladen, 2,
        reason: 'ein neu abgepfiffener Spieltag braucht die volle Statistik');
  });
}
