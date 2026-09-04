import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/features/fantasy/models/fantasy_models.dart';

/// **Wer keinen Torwart mehr hat, spielt mit zehn.**
///
/// Gemeldet am 04.09.2026: „Bei Lewins Aufstellung passt irgendetwas gar
/// nicht." Sein Kader hatte 14 Spieler und keinen Torwart — der einzige war am
/// 29.08. zu Leeds gewechselt, und der Abgangs-Lauf (0117) hatte ihn korrekt
/// aus dem Kader genommen. Danach war **keine** Formation mehr gültig: Der
/// Schirm stand dauerhaft auf „noch nicht vollständig", gespeichert wurde nie,
/// und er ging ohne eigenes Zutun mit null Punkten in jeden Spieltag.
///
/// Die Ausnahme hängt am Kader, nicht an der Auswahl — sonst wäre aus der
/// Notlösung eine frei wählbare Formation mit zehn Feldspielern geworden.
/// **Dieselbe Regel steht ein zweites Mal in SQL** (`fantasy_set_lineup`,
/// Migration 0120); dieser Test hält die Dart-Seite.
void main() {
  const r = RosterConfig(
    gk: 1,
    def: 4,
    mid: 4,
    fwd: 2,
    bench: 5,
    defMin: 3,
    defMax: 5,
    midMin: 2,
    midMax: 5,
    fwdMin: 1,
    fwdMax: 4,
  );

  test('mit Torwart im Kader bleibt es bei elf', () {
    expect(
      r.isValidFormation(gkCount: 1, defCount: 4, midCount: 4, fwdCount: 2),
      isTrue,
    );
    // Zehn Feldspieler ohne Torwart sind für ihn keine Elf.
    expect(
      r.isValidFormation(gkCount: 0, defCount: 4, midCount: 4, fwdCount: 2),
      isFalse,
      reason: 'wer einen Torwart hat, muss ihn aufstellen',
    );
  });

  test('ohne Torwart im Kader gelten zehn Feldspieler', () {
    expect(
      r.isValidFormation(
        gkCount: 0,
        defCount: 4,
        midCount: 4,
        fwdCount: 2,
        torwartImKader: false,
      ),
      isTrue,
    );
  });

  test('die Spannen der Feldspieler gelten unverändert weiter', () {
    // 2 Abwehrspieler sind auch ohne Torwart zu wenig (defMin 3) …
    expect(
      r.isValidFormation(
        gkCount: 0,
        defCount: 2,
        midCount: 5,
        fwdCount: 3,
        torwartImKader: false,
      ),
      isFalse,
    );
    // … und die Kopplung „vier Stürmer nur mit vier Abwehr" ebenso.
    expect(
      r.isValidFormation(
        gkCount: 0,
        defCount: 3,
        midCount: 3,
        fwdCount: 4,
        torwartImKader: false,
      ),
      isFalse,
    );
    expect(
      r.isValidFormation(
        gkCount: 0,
        defCount: 4,
        midCount: 2,
        fwdCount: 4,
        torwartImKader: false,
      ),
      isTrue,
    );
  });

  test('ein Torwart in der Elf ist auch ohne Kader-Torwart unmöglich', () {
    // Der Fall kann nur entstehen, wenn die Auswahl nicht zum Kader passt —
    // dann ist sie ungültig, statt stillschweigend als Elf durchzugehen.
    expect(
      r.isValidFormation(
        gkCount: 1,
        defCount: 4,
        midCount: 4,
        fwdCount: 2,
        torwartImKader: false,
      ),
      isFalse,
    );
  });
}
