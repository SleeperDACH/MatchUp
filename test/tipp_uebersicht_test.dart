import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/tippspiel/logic/tipp_uebersicht.dart';
import 'package:matchup/features/tippspiel/models/tip.dart';
import 'package:matchup/features/tippspiel/models/tip_round.dart';

/// Die Übersicht einer Tipprunde (09.11.2026, Redesign „Richtung B"):
/// derselbe Stand wie die Tabelle, dieselbe Woche wie der Tippen-Reiter.
void main() {
  // Woche Do 05.11. – Mi 11.11.2026; „jetzt" ist Samstag 18 Uhr.
  final jetzt = DateTime(2026, 11, 7, 18);

  Fixture spiel(String id, DateTime anstoss, {int? h, int? a}) => Fixture(
        id: id,
        leagueId: 'bundesliga',
        season: 2026,
        round: 10,
        roundName: '10. Spieltag',
        kickoff: anstoss,
        home: const TeamRef(id: 'a', name: 'A', shortName: 'A'),
        away: const TeamRef(id: 'b', name: 'B', shortName: 'B'),
        status: h == null ? FixtureStatus.scheduled : FixtureStatus.finished,
        homeScore: h,
        awayScore: a,
      );

  final alt = spiel('alt', DateTime(2026, 10, 31, 15, 30), h: 1, a: 0);
  final samstag = spiel('sa', DateTime(2026, 11, 7, 15, 30), h: 2, a: 1);
  final sonntag1 = spiel('so1', DateTime(2026, 11, 8, 15, 30));
  final sonntag2 = spiel('so2', DateTime(2026, 11, 8, 17, 30));
  final fixtures = [alt, samstag, sonntag1, sonntag2];

  RoundMember m(String id) => RoundMember(userId: id, username: id);
  MemberTip t(String u, String f, int h, int a) =>
      MemberTip(userId: u, fixtureId: f, homeGoals: h, awayGoals: a);

  final mitglieder = [m('ana'), m('ich'), m('jojo'), m('max'), m('zoe')];
  final tipps = [
    t('ana', 'alt', 1, 0), t('ana', 'sa', 2, 1), // 4 + 4
    t('jojo', 'alt', 1, 0), // 4
    t('max', 'sa', 1, 0), // 3 (Tordifferenz)
    t('ich', 'sa', 3, 1), // 2 (Tendenz)
    t('ich', 'so1', 1, 1),
  ];

  TippUebersicht rechne({String? ich = 'ich'}) => TippUebersicht.berechnen(
        members: mitglieder,
        tips: tipps,
        seasonFixtures: fixtures,
        rules: const ScoringRules(),
        myId: ich,
        jetzt: jetzt,
      );

  test('Stand wie die Tabelle: Punkte, Platz, Mitglieder', () {
    final u = rechne();
    expect(u.punkte, 2);
    expect(u.rang, 4, reason: 'ana 8, jojo 4, max 3, ich 2');
    expect(u.mitglieder, 5);
  });

  test('Wochenpunkte nur aus der laufenden Woche', () {
    expect(rechne().wochePunkte, 2);
  });

  test('offene Tipps: nur kommende Spiele der Woche, Frist = erstes offenes', () {
    final u = rechne();
    expect(u.anstehend, 2);
    expect(u.offen, 1, reason: 'so1 ist getippt, so2 nicht');
    expect(u.frist, sonntag2.kickoff.toLocal());
  });

  test('Kurztabelle: die ersten drei und ich dahinter', () {
    final k = rechne().kurztabelle;
    expect([for (final p in k) p.mitglied.userId], ['ana', 'jojo', 'max', 'ich']);
    expect([for (final p in k) p.rang], [1, 2, 3, 4]);
    expect(k.last.ich, isTrue);
    expect(k.where((p) => p.ich).length, 1);
  });

  test('wer oben steht, steht nicht doppelt da', () {
    final k = rechne(ich: 'ana').kurztabelle;
    expect(k.length, 3);
    expect(k.first.ich, isTrue);
  });

  test('ohne Mitgliedschaft: kein Platz, keine offenen Tipps', () {
    final u = rechne(ich: 'fremd');
    expect(u.rang, isNull);
    expect(u.offen, 0);
    expect(u.kurztabelle.length, 3);
  });
}
