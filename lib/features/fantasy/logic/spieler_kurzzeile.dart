/// **Die zwei kleinen Zeilen unter dem Namen einer MatchUp-Karte.**
///
/// Gewünscht nach dem Vorbild Sleeper: „dass die Spielerkarten nochmal mehr
/// Information bringen". Dort steht unter jedem Spieler, wie das Spiel seines
/// Teams lief („L 21-45 vs DET"), und was er darin gemacht hat („12 CAR,
/// 22 YD"). Übersetzt auf Fußball:
///
/// * **Spielzeile** — vor dem Anpfiff Gegner und Anstoß, danach Ausgang und
///   Ergebnis aus Sicht seines Vereins.
/// * **Statistikzeile** — gab es bis zum 17.10.2026 („90' · 4 Paraden"); auf
///   Ansage raus, sie machte die Karte unruhig. Woher die Punkte kommen, sagt
///   die Aufschlüsselung hinter der Zahl.
///
/// Beides rein und ohne Flutter, damit es prüfbar ist.
library;

import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';
import 'naechstes_spiel.dart';

/// Ausgang des Spiels **seines Vereins** — nicht des Fantasy-Duells.
enum VereinsAusgang { sieg, unentschieden, niederlage }

class SpielZeile {
  const SpielZeile(this.text, {this.ausgang, this.laeuft = false, this.anstoss});

  final String text;

  /// Vor dem Anpfiff der Anstoß („Sa 15:30") — **eigene Zeile**, nicht an den
  /// Gegner gehängt: In einer halben Kartenbreite stand sonst
  /// „vs M05 · S…". Die dritte Zeile ist vor dem Anpfiff ohnehin frei, sie
  /// trägt erst danach die Statistik.
  final String? anstoss;

  /// Nur für beendete Spiele gesetzt; trägt die Farbe des Buchstabens.
  final VereinsAusgang? ausgang;

  /// Das Spiel läuft gerade — die Zeile steht dann in der Live-Farbe.
  final bool laeuft;
}

/// „vs M05" zu Hause, „@ M05" auswärts — dieselbe Schreibweise wie bei Sleeper
/// und in jeder amerikanischen Sportapp; kurz genug für eine halbe Kartenbreite.
String _gegen(NaechstesSpiel s) =>
    '${s.heim ? 'vs' : '@'} ${vereinsKuerzel(s.gegner)}';

/// Die Spielzeile, oder `null`, wenn sein Verein an dem Spieltag frei hat.
SpielZeile? spielZeile(NaechstesSpiel? s, {required DateTime jetzt}) {
  if (s == null) return null;
  final stand = s.eigeneTore != null && s.gegnerTore != null
      ? '${s.eigeneTore}:${s.gegnerTore}'
      : null;
  if (s.status == FixtureStatus.finished && stand != null) {
    final ausgang = s.eigeneTore! > s.gegnerTore!
        ? VereinsAusgang.sieg
        : s.eigeneTore! < s.gegnerTore!
            ? VereinsAusgang.niederlage
            : VereinsAusgang.unentschieden;
    final buchstabe = switch (ausgang) {
      VereinsAusgang.sieg => 'S',
      VereinsAusgang.unentschieden => 'U',
      VereinsAusgang.niederlage => 'N',
    };
    return SpielZeile('$buchstabe $stand ${_gegen(s)}', ausgang: ausgang);
  }
  // **Läuft, sobald angepfiffen** — nicht erst, wenn der Spielplan „live"
  // meldet. Der wird nur alle paar Minuten gespiegelt; die Uhr ist genauer.
  final laeuft = s.status == FixtureStatus.live ||
      (s.status != FixtureStatus.finished && !s.anpfiff.isAfter(jetzt));
  if (laeuft) {
    return SpielZeile('${stand ?? '0:0'} ${_gegen(s)}', laeuft: true);
  }
  return SpielZeile(_gegen(s), anstoss: anpfiffKurz(s.anpfiff));
}
