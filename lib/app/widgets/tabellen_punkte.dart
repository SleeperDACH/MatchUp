import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../theme.dart';

/// **Die Punktzahl einer Tabellenzeile — rot, solange sie sich noch ändern
/// kann.**
///
/// Die Ligatabelle dieser App rechnet laufende Spiele längst mit
/// (`mergeLiveResults`): Führt eine Mannschaft zur Halbzeit, stehen ihre drei
/// Punkte schon in der Spalte. **Zu sehen war das nicht** — eine vorläufige
/// Zahl sah aus wie eine feste, und wer die Tabelle am Samstagnachmittag
/// aufschlug, konnte nicht erkennen, welche Ränge noch wackeln.
///
/// Rot heißt in dieser App „läuft gerade": derselbe Ton wie beim Live-Punkt im
/// Live-Tab, beim Spielstand einer laufenden Partie und in der Tipp-Tabelle.
/// **Und wie dort steht kein Wort daneben** — die Farbe trägt es allein, sonst
/// stünde dieselbe Auskunft zweimal in einer Zeile, die für vier Zahlen
/// gebaut ist.
class TabellenPunkte extends StatelessWidget {
  const TabellenPunkte({super.key, required this.punkte, required this.live});

  final int punkte;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$punkte',
      textAlign: TextAlign.end,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: live ? MatchUpColors.red : null,
        // Gleichbreite Ziffern: Die Spalte steht still, während der Wert
        // während eines Spiels von 34 auf 37 springt.
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Die Mannschaften, deren Spiel **gerade läuft** — als Menge von Team-IDs.
///
/// Aus dem Spielplan, nicht aus der Tabelle: Die Tabelle sagt, wie viele
/// Punkte jemand hat, nicht, ob er gerade spielt.
Set<String> laufendeTeams(List<Fixture> fixtures) => {
      for (final f in fixtures)
        if (f.status == FixtureStatus.live) ...[f.home.id, f.away.id],
    };
