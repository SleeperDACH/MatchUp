import 'package:flutter/material.dart';

import '../../core/logic/tabellen_zonen.dart';
import '../farben.dart';
import '../typografie.dart';

/// Farbe einer Zone im aktuellen Modus. Auf Dunkel die festen Werte der
/// Zone, auf Hell dieselben Töne in der Fassung, die auf Weiß lesbar ist —
/// ein gelber Strich auf Weiß verschwindet sonst.
Color zonenFarbe(BuildContext context, TabellenZone zone) {
  if (!context.istHell) return zone.farbe;
  final f = context.farben;
  return switch (zone) {
    TabellenZone.meister || TabellenZone.aufstieg => f.gold,
    TabellenZone.championsLeague => f.blau,
    TabellenZone.europaLeague => f.orange,
    TabellenZone.conferenceLeague => f.tuerkis,
    TabellenZone.relegation => f.violett,
    TabellenZone.abstieg => f.rot,
  };
}

/// Der Platz einer Tabellenzeile mit **einem farbigen Strich davor** — der
/// Zone (Meister, Champions League, Abstieg …). Farbe als Strich, nicht als
/// Fläche: Eine ganz eingefärbte Zeile riefe bei achtzehn Zeilen in sechs
/// Farben zu laut. Ohne Zone bleibt die Stelle leer, damit die Zahlen
/// untereinander fluchten.
class ZonenRang extends StatelessWidget {
  const ZonenRang({
    super.key,
    required this.rang,
    required this.zone,
    this.fett = false,
  });

  final int rang;
  final TabellenZone? zone;
  final bool fett;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        child: Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: zone == null
                    ? Colors.transparent
                    : zonenFarbe(context, zone!),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$rang',
                style: TextStyle(
                  fontWeight: fett ? FontWeight.bold : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
}

/// Die Legende unter einer Tabelle: je Zone ein Punkt und das Wort.
class ZonenLegende extends StatelessWidget {
  const ZonenLegende({super.key, required this.leagueId, required this.teams});

  final String? leagueId;
  final int teams;

  @override
  Widget build(BuildContext context) {
    final zonen = zonenDerLiga(leagueId, teams);
    if (zonen.isEmpty) return const SizedBox.shrink();
    final grau = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (final z in zonen)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: zonenFarbe(context, z), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(z.name,
                    style: TextStyle(fontSize: Schrift.label, color: grau)),
              ],
            ),
        ],
      ),
    );
  }
}
