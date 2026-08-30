
/// Wann sperrt die Aufstellung? **Je Spieler, zum Anpfiff seines Vereins.**
///
/// Vorher galt ein Riegel für den ganzen Spieltag (der früheste Anpfiff der
/// Runde). Wer das Freitagsspiel verpasst hatte, konnte auch seinen
/// Sonntagsspieler nicht mehr tauschen — zwei Tage Sperre für null
/// Informationsvorsprung.
///
/// Maßgeblich ist der Server (`fantasy_set_lineup`, Migration 0084); das hier
/// ist die Oberfläche dazu. Beide müssen dieselbe Regel meinen, sonst zeigt
/// die App ein Feld als bedienbar, das der Server dann ablehnt.
library;

import '../../../core/models/models.dart';
import '../models/fantasy_models.dart';

/// Anpfiff je Verein für einen Spieltag.
///
/// Derselbe Spieltag kann doppelt gespiegelt sein (`openligadb:` und
/// `sportmonks:`) — die frühere Zeit gewinnt, sie ist bei Dubletten dieselbe.
Map<String, DateTime> anpfiffJeVerein(List<Fixture> spiele, int runde) {
  final out = <String, DateTime>{};
  for (final f in spiele) {
    if (f.round != runde) continue;
    for (final name in [f.home.name, f.away.name]) {
      final da = out[name];
      if (da == null || f.kickoff.isBefore(da)) out[name] = f.kickoff;
    }
  }
  return out;
}

/// Ist dieser Spieler festgenagelt, weil sein Spiel schon läuft?
///
/// **Kein Spiel gefunden heißt nicht gesperrt.** Der Kader kann Spieler
/// enthalten, deren Verein an dem Spieltag nicht spielt oder gar nicht mehr in
/// der Liga ist. Sie zu bewegen bringt niemandem einen Vorteil — sie punkten
/// in dieser Runde ohnehin nicht.
bool spielerGesperrt(
  FantasyPlayer spieler,
  Map<String, DateTime> anpfiff,
  DateTime jetzt,
) {
  final kick = anpfiff[spieler.club];
  return kick != null && !jetzt.isBefore(kick);
}

/// Wie viele der aufgestellten Spieler sind noch frei?
///
/// Nur dafür da, der Fußzeile eine ehrliche Auskunft zu geben: „alles
/// gesperrt" ist ein anderer Zustand als „drei noch offen", und beide sahen
/// vorher gleich aus.
int nochFrei(
  Iterable<FantasyPlayer> spieler,
  Map<String, DateTime> anpfiff,
  DateTime jetzt,
) =>
    spieler.where((p) => !spielerGesperrt(p, anpfiff, jetzt)).length;

/// **Läuft das Spiel dieses Vereins in der aktuell zählenden Runde schon?**
///
/// Die Frage entscheidet, ob ein freier Spieler geholt werden darf. Sie ist
/// nicht dieselbe wie [spielerGesperrt]: Dort geht es um einen Spieler, der
/// bereits im Kader steht, und die Runde ist bekannt. Hier ist die Runde erst
/// zu bestimmen — die niedrigste, die noch nicht vollständig abgepfiffen ist.
///
/// **Maßgeblich ist der Server** (`fantasy_spieler_laeuft`, Migration 0094);
/// das hier ist die Oberfläche dazu. Laufen die beiden auseinander, zeigt die
/// App ein grünes Plus, und der Server antwortet mit einer Fehlermeldung —
/// genau der Zustand, der als „es passiert überhaupt nichts" gemeldet wurde.
bool vereinSpieltGerade(
  String verein,
  Map<String, DateTime> anpfiffDerRunde,
  DateTime jetzt,
) {
  final kick = anpfiffDerRunde[verein];
  return kick != null && !jetzt.isBefore(kick);
}
