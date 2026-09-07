import 'package:intl/intl.dart';

import '../../../core/logic/vereins_kuerzel.dart';
import '../../../core/models/models.dart';

/// **Wann ist er wieder da?**
///
/// Gewünscht: *„Wenn ein Spieler verletzt ist, wird die voraussichtliche
/// Rückkehr angezeigt. Ob das jetzt ein genaues Datum, ein genauer Spieltag,
/// eine ungefähre Anzahl an Wochen oder Monaten ist, ist egal. Wenn es nicht
/// bekannt ist, dann Rückkehr unbekannt."*
///
/// **Die Quelle kennt genau ein Feld dafür**, `end_date`, und füllt es
/// selten: Gemessen am 07.09.2026 tragen **24 von 109** Ausfällen ein
/// Rückkehrdatum. Für die übrigen gibt es nichts zu rechnen — kein zweites
/// Feld, keine Dauer je Verletzungsart, keine Prognose. „Rückkehr unbekannt"
/// ist deshalb keine Notlösung, sondern in vier von fünf Fällen die richtige
/// Auskunft.
///
/// Was hier passiert, ist allein die Aufbereitung: ein Datum, dazu eine grobe
/// Spanne, weil „30. September" allein nicht sagt, ob das nah oder fern ist.

/// Ein Satz zur Rückkehr, oder die ehrliche Auskunft, dass es keinen gibt.
///
/// Die Spanne wird **grob** genannt, nicht auf den Tag: Ein Rückkehrdatum aus
/// dieser Quelle ist eine Schätzung, und „in 24 Tagen" täuschte eine Genauigkeit
/// vor, die dahinter nicht steckt.
String rueckkehrSatz(DateTime? bis, DateTime jetzt) {
  if (bis == null) return 'Rückkehr unbekannt';

  final heute = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final tag = DateTime(bis.year, bis.month, bis.day);
  final tage = tag.difference(heute).inDays;
  final datum = DateFormat('d. MMMM', 'de_DE').format(tag);

  // **Ein vergangenes Datum ist kein Fehler, sondern eine Verzögerung.** Die
  // Quelle schreibt es nicht zurück; er sollte längst spielen und tut es
  // nicht. Das als „zurück am 10. September" hinzuschreiben wäre falsch.
  if (tage < 0) return 'Rückkehr war für den $datum geplant';
  if (tage == 0) return 'Zurück ab heute';
  if (tage == 1) return 'Zurück ab morgen';
  if (tage <= 13) return 'Zurück ab $datum · in $tage Tagen';
  if (tage <= 70) {
    final wochen = (tage / 7).round();
    return 'Zurück ab $datum · in etwa $wochen Wochen';
  }
  final monate = (tage / 30).round();
  return 'Zurück ab $datum · in etwa $monate Monaten';
}

/// Der erste Spieltag seines Vereins ab diesem Tag — die Zahl, die einen
/// Manager wirklich interessiert.
///
/// Ein Datum beantwortet „wann", ein Spieltag beantwortet „ab wann kann ich
/// ihn wieder aufstellen". Verglichen wird über [vereinKanonisch], weil
/// Kader und Spielplan denselben Verein verschieden schreiben („1. FC Köln"
/// gegen „FC Köln") — dieselbe Reparatur wie in Migration 0108.
///
/// `null`, wenn der Spielplan nichts hergibt: Ein geratener Spieltag wäre
/// schlechter als keiner.
int? ersterSpieltagAb(DateTime tag, List<Fixture> spielplan, String verein) {
  final gesucht = vereinKanonisch(verein);
  final grenze = DateTime(tag.year, tag.month, tag.day);
  int? bester;
  DateTime? bestesDatum;
  for (final f in spielplan) {
    if (vereinKanonisch(f.home.name) != gesucht &&
        vereinKanonisch(f.away.name) != gesucht) {
      continue;
    }
    final anstoss = f.kickoff.toLocal();
    if (anstoss.isBefore(grenze)) continue;
    if (bestesDatum == null || anstoss.isBefore(bestesDatum)) {
      bestesDatum = anstoss;
      bester = f.round;
    }
  }
  return bester;
}
