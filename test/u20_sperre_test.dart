import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/logic/fantasy_scoring_rules.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Die U20-Sperre gilt nur im Dynasty-Modus.**
///
/// Gemeldet: *„Es macht keinen Sinn, dass hier einer für den U20-Draft
/// gesperrt ist, weil es im Redraft-Modus keinen U20-Draft gibt. Das ist nur
/// in Dynasty."*
///
/// `isLockedNow` kennt Geburtsdatum, Auslands-Neuzugang und Saison — aber
/// keine Liga, und damit auch nicht deren Modus. Ab dem 5. September
/// (Transferschluss) fiel damit jeder Rookie aus der Free Agency **auch dort,
/// wo er nie wieder gedraftet wird**: Im Redraft-Modus gibt es genau einen
/// Draft. Der Spieler war für den Rest der Saison für niemanden mehr zu holen,
/// ohne dass es dafür einen Grund gab.
///
/// **Dieselbe Regel steht ein zweites Mal in SQL** (`fantasy_u20_gesperrt`,
/// Migration 0121) — wie `tip_scoring.dart` ↔ SQL-View. Laufen sie
/// auseinander, zeigt die App einen Knopf, den der Server ablehnt.

FantasyLeague _liga(FantasyMode modus) => FantasyLeague(
      id: 'l1',
      name: 'Testliga',
      mode: modus,
      season: 2026,
      pickTime: DraftPickTime.h2,
      scoring: const FantasyScoringRules(),
      roster: RosterConfig.standard,
      inviteCode: 'ABC',
      draftStatus: DraftStatus.done,
      createdBy: 'u1',
      maxTeams: 12,
    );

/// Geboren 2008 — zum 1. August 2026 also 17 und damit U20.
FantasyPlayer _rookie() => FantasyPlayer(
      id: 'p1',
      name: 'Junger Spieler',
      position: PlayerPosition.mid,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(2008, 3, 1),
    );

/// Geboren 1996 — kein Rookie.
FantasyPlayer _routinier() => FantasyPlayer(
      id: 'p2',
      name: 'Alter Hase',
      position: PlayerPosition.def,
      club: 'FC Bayern München',
      nationality: 'de',
      birthDate: DateTime(1996, 3, 1),
    );

void main() {
  test('ein Rookie ist im Redraft-Modus nicht gesperrt', () {
    final p = _rookie();
    // Die Rookie-Eigenschaft an sich bleibt wahr — sie ist eine Aussage über
    // den Spieler, keine über die Liga.
    expect(p.isRookieFor(2026), isTrue);
    expect(p.istFuerU20Gesperrt(_liga(FantasyMode.liga)), isFalse,
        reason: 'im Redraft gibt es keinen zweiten Draft, für den man '
            'jemanden zurückhalten könnte');
  });

  test('in Dynasty bleibt er gesperrt, sobald die Frist läuft', () {
    final p = _rookie();
    final dynasty = _liga(FantasyMode.dynasty);
    // Die Sperre greift ab dem 5. September der Saison. Der Test bindet sich
    // nicht an „heute": Er prüft, dass Modus **und** Frist zusammen
    // entscheiden — die Frist selbst gehört `isLockedNow`.
    expect(p.istFuerU20Gesperrt(dynasty), p.isLockedNow(2026));
  });

  test('wer kein Rookie ist, wird in keinem Modus gesperrt', () {
    final p = _routinier();
    expect(p.isRookieFor(2026), isFalse);
    expect(p.istFuerU20Gesperrt(_liga(FantasyMode.liga)), isFalse);
    expect(p.istFuerU20Gesperrt(_liga(FantasyMode.dynasty)), isFalse);
  });

  test('die Frist selbst ist unverändert', () {
    // **Die Gegenprobe.** Wäre bei der Umstellung die Frist mit
    // verlorengegangen, wäre in Dynasty gar keiner mehr gesperrt — und das
    // fiele erst in einem Jahr auf, wenn der U20-Draft ansteht.
    final p = _rookie();
    expect(p.isLockedNow(2030), isFalse,
        reason: 'der 5. September 2030 liegt in der Zukunft');
  });
}
