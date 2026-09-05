import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/models/models.dart';
import 'package:matchup/features/fantasy/logic/waiver_fenster.dart';

/// **Die Regel stimmte, die Uhr stand.**
///
/// Gemeldet: *„Ich habe versucht, Hollerbach gegen Ebimbe, der aktuell spielt,
/// einen Waiver-Antrag zu stellen. Das hat nicht funktioniert."*
///
/// Server und Client meinten dasselbe — nachgemessen an den echten Anpfiffen
/// des 2. Spieltags: Schalke stößt um 18:30 an, Mainz erst am Sonntag, die
/// Frist liegt auf Montag 15:00. Beide sagen „Ebimbe liegt auf dem Waiver".
///
/// **Der Unterschied war der Zeitpunkt der Frage.** Die Free Agency rechnete
/// `DateTime.now()` einmal je Aufbau, und nichts baute den Schirm neu, wenn
/// ein Anpfiff vorbeiging. Wer die Liste um 18:20 offen hatte, sah um 18:35
/// immer noch das grüne Plus — und der Server antwortete mit „Er liegt auf dem
/// Waiver – bitte per Antrag holen".
///
/// Dieser Test hält die Regel an beiden Seiten des Anpfiffs fest; die Uhr
/// selbst sitzt im Schirm (einmaliger Timer auf den nächsten Anpfiff).

Fixture _f(String heim, String gast, DateTime anstoss, FixtureStatus status) =>
    Fixture(
      id: 'sportmonks:${heim.hashCode}',
      leagueId: 'bundesliga',
      season: 2026,
      round: 2,
      roundName: '2. Spieltag',
      kickoff: anstoss,
      home: TeamRef(id: heim, name: heim, shortName: heim),
      away: TeamRef(id: gast, name: gast, shortName: gast),
      status: status,
    );

/// Der echte 2. Spieltag, wie er am 05.09.2026 im Spielplan stand.
final _spieltag = [
  _f('VfB Stuttgart', 'FC Köln', DateTime(2026, 9, 4, 20, 30),
      FixtureStatus.finished),
  _f('Werder Bremen', 'RB Leipzig', DateTime(2026, 9, 5, 15, 30),
      FixtureStatus.finished),
  _f('Schalke 04', 'FC Bayern München', DateTime(2026, 9, 5, 18, 30),
      FixtureStatus.live),
  _f('Hamburger SV', 'FSV Mainz 05', DateTime(2026, 9, 6, 15, 30),
      FixtureStatus.scheduled),
  _f('Eintracht Frankfurt', 'FC Augsburg', DateTime(2026, 9, 6, 17, 30),
      FixtureStatus.scheduled),
];

void main() {
  test('vor dem Anpfiff ist der Schalker frei', () {
    final vorher = DateTime(2026, 9, 5, 18, 20);
    expect(vereinAufWire('FC Schalke 04', _spieltag, vorher), isFalse,
        reason: 'bis zum Anpfiff holt man ihn direkt');
  });

  test('nach dem Anpfiff liegt er auf dem Waiver', () {
    final nachher = DateTime(2026, 9, 5, 18, 35);
    expect(vereinAufWire('FC Schalke 04', _spieltag, nachher), isTrue,
        reason: 'ab dem Anpfiff seines Vereins geht nur noch der Antrag');
  });

  test('fünfzehn Minuten entscheiden — genau daran hing der Fehler', () {
    // **Die beiden Antworten unterscheiden sich, ohne dass sich der Spielplan
    // ändert.** Wer die Antwort einmal berechnet und stehen lässt, zeigt
    // danach den falschen Knopf. Das ist der ganze Fehler, und deshalb hat der
    // Schirm jetzt eine Uhr.
    expect(
      vereinAufWire('FC Schalke 04', _spieltag, DateTime(2026, 9, 5, 18, 20)),
      isNot(vereinAufWire(
          'FC Schalke 04', _spieltag, DateTime(2026, 9, 5, 18, 35))),
    );
  });

  test('der Sonntagsspieler bleibt derweil frei', () {
    // Hollerbach spielt Sonntag — abgeben darf man ihn also noch.
    final nachher = DateTime(2026, 9, 5, 18, 35);
    expect(vereinAufWire('1. FSV Mainz 05', _spieltag, nachher), isFalse);
  });

  test('die Frist ist Montag 15:00', () {
    expect(waiverFrist(_spieltag, 2), DateTime(2026, 9, 7, 15));
    expect(fristKurz(waiverFrist(_spieltag, 2)!), 'Mo, 15:00');
  });

  test('nach der Frist ist die Wire-Phase vorbei', () {
    expect(wireRunde(_spieltag, DateTime(2026, 9, 5, 18, 35)), 2);
    expect(wireRunde(_spieltag, DateTime(2026, 9, 7, 15, 1)), isNull,
        reason: 'danach gilt wieder „first come, first served"');
  });
}
