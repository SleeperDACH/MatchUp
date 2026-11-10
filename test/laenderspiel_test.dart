import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/data/laenderspiel/laenderspiel_daten.dart';
import 'package:matchup/core/data/openligadb/openligadb_provider.dart';
import 'package:matchup/core/models/match_detail.dart';
import 'package:matchup/core/models/models.dart';

/// Länderspiele (09.11.2026, auf Ansage: „erstmal nur die Deutschlandspiele").
/// Quelle OpenLigaDB `DFBN`; der Spielverlauf im Detail liest Ereignisse, also
/// werden die Tore dorthin übersetzt.
void main() {
  Map<String, dynamic> tor(int minute, int h, int a,
          {String name = 'F. Nmecha',
          bool nachspiel = false,
          bool elfmeter = false,
          bool eigentor = false}) =>
      {
        'matchMinute': minute,
        'scoreTeam1': h,
        'scoreTeam2': a,
        'goalGetterName': name,
        'isOvertime': nachspiel,
        'isPenalty': elfmeter,
        'isOwnGoal': eigentor,
      };

  test('Tor mit Minute, Spieler und Stand', () {
    final e = OpenLigaDbProvider.torAlsEreignis(tor(32, 0, 1), heimTraf: false)!;
    expect(e.minute, 32);
    expect(e.extra, isNull);
    expect(e.type, 'Goal');
    expect(e.player, 'F. Nmecha');
    expect(e.result, '0-1');
    expect(e.forHomeTeam, isFalse);
  });

  test('Nachspielzeit: 92 mit isOvertime wird 90+2', () {
    // Gakpo, Niederlande–Deutschland 1:1 (24.09.2026).
    final e = OpenLigaDbProvider.torAlsEreignis(
        tor(92, 1, 1, name: 'Cody Gakpo', nachspiel: true),
        heimTraf: true)!;
    expect((e.minute, e.extra), (90, 2));
  });

  test('Elfmeter und Eigentor tragen ihren Typ', () {
    expect(
        OpenLigaDbProvider.torAlsEreignis(tor(10, 1, 0, elfmeter: true),
                heimTraf: true)!
            .type,
        'Penalty');
    expect(
        OpenLigaDbProvider.torAlsEreignis(tor(10, 1, 0, eigentor: true),
                heimTraf: true)!
            .type,
        'Own Goal');
  });

  test('ohne Minute kein Ereignis', () {
    expect(
        OpenLigaDbProvider.torAlsEreignis(
            {'scoreTeam1': 1, 'scoreTeam2': 0}, heimTraf: true),
        isNull);
  });

  test('Deutschland steht im Live-Tab, nicht bei den Wettbewerben', () {
    expect(Leagues.liveTab.first, Leagues.deutschland);
    expect(Leagues.all, isNot(contains(Leagues.deutschland)));
    expect(Leagues.byId('deutschland'), Leagues.deutschland);
    expect(Leagues.deutschland.seasonFor(DateTime(2026, 11, 13)), 2026);
  });

  group('API-Football-Ergänzung', () {
    // Echte Antwort der Function `laenderspiel` (umgeformt aus API-Football,
    // Köln–Leverkusen 1:2 am 08.11.2026 — ein Länderspiel lag im Fenster
    // des Gratis-Tarifs nicht).
    final j = jsonDecode(
      File('test/fixtures/laenderspiel_af_koeln_leverkusen.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

    MatchDetail basis({int? heim, int? gast}) => MatchDetail(
          id: 'openligadb:1',
          home: const TeamRef(id: 'a', name: 'Deutschland', shortName: 'GER'),
          away: const TeamRef(id: 'b', name: 'Serbien', shortName: 'SRB'),
          kickoff: DateTime.utc(2026, 11, 13, 19, 45),
          status: FixtureStatus.finished,
          homeScore: heim,
          awayScore: gast,
          goals: const [],
        );

    test('Aufstellung mit Formation und Raster', () {
      final d = ergaenzeLaenderspiel(basis(heim: 1, gast: 2), j);
      expect(d.homeFormation, '3-5-2');
      expect(d.awayFormation, '4-2-3-1');
      expect(d.lineups.where((p) => p.starting).length, 22);
      final tw = d.lineups.first;
      expect((tw.name, tw.row, tw.col, tw.position), ('M. Schwäbe', 1, 1, 1));
    });

    test('Wechsel: eingewechselt vorn, ausgewechselt dahinter', () {
      final d = ergaenzeLaenderspiel(basis(heim: 1, gast: 2), j);
      final w = d.events.firstWhere((e) => e.type == 'Substitution');
      expect(w.minute, 74);
      expect(w.player, 'Ísak Bergmann Jóhannesson');
      expect(w.related, 'Tom Krauß');
      final krauss = d.lineups.firstWhere((p) => p.name == 'T. Krauß');
      expect(krauss.starting, isTrue, reason: 'der Ausgewechselte begann');
      expect(w.relatedPlayerId, krauss.playerId);
    });

    test('Tore mit Vorlage, Stand und Nachspielzeit; Karten', () {
      final d = ergaenzeLaenderspiel(basis(heim: 1, gast: 2), j);
      final tore = d.events.where((e) => e.type == 'Goal').toList();
      expect([for (final t in tore) t.result], ['0-1', '0-2', '1-2']);
      expect((tore.last.minute, tore.last.extra), (90, 2));
      expect(tore[1].related, 'Ibrahim Maza');
      expect(d.events.where((e) => e.type == 'Yellowcard').length, 11);
      expect(d.stats.first.label, 'Ballbesitz %');
      expect((d.stats.first.home, d.stats.first.away), (38, 62));
    });

    test('Stand bleibt von OpenLigaDB, fehlt er, kommt er von dort', () {
      expect(ergaenzeLaenderspiel(basis(heim: 3, gast: 0), j).homeScore, 3);
      final ohne = ergaenzeLaenderspiel(basis(), j);
      expect((ohne.homeScore, ohne.awayScore), (1, 2));
    });

    test('nur Spiele der Nationalmannschaft', () {
      expect(istLaenderspiel(basis()), isTrue);
      final verein = MatchDetail(
        id: 'openligadb:2',
        home: const TeamRef(id: 'a', name: 'Bayern', shortName: 'FCB'),
        away: const TeamRef(id: 'b', name: 'BVB', shortName: 'BVB'),
        kickoff: DateTime.utc(2026),
        status: FixtureStatus.scheduled,
        homeScore: null,
        awayScore: null,
        goals: const [],
      );
      expect(istLaenderspiel(verein), isFalse);
    });
  });
}
