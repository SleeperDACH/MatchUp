import 'package:flutter/material.dart';

import '../../../app/typografie.dart';
import '../../../core/logic/vereins_kuerzel.dart';
import '../../tippspiel/ui/team_badge.dart';
import '../logic/naechstes_spiel.dart';

/// **Eine Partie in einer Zeile: Wappen des Gegners und Anstoß**
/// (19.10.2026, auf Ansage: „diese Schrift von den Partien und Anstoßzeiten
/// … sieht unordentlich aus").
///
/// Vorher stand dort „FCA · Sa 15:30" — Kürzel, Trennpunkt und Zeit in
/// derselben kleinen, fetten Schrift. Jetzt trägt das **Wappen** den Gegner,
/// und die Zeit steht in normaler Stärke mit gleich breiten Ziffern. Ohne Wappen (kein Spielplan-Team) fällt die
/// Marke auf das Kürzel zurück.
class SpielMarke extends StatelessWidget {
  const SpielMarke({
    super.key,
    required this.spiel,
    this.wappen = 14,
    this.farbe,
    this.groesse = Schrift.label,
    this.mitZeit = true,
  });

  final NaechstesSpiel spiel;
  final double wappen;
  final Color? farbe;
  final double groesse;

  /// Tag und Anstoß hinter dem Wappen (MatchUp); im Kader nur das Wappen.
  final bool mitZeit;

  @override
  Widget build(BuildContext context) {
    final f = farbe ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final stil = TextStyle(
      fontSize: groesse,
      fontWeight: FontWeight.w500,
      height: 1.0,
      color: f,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final team = spiel.gegnerTeam;
    // **Kein H/A mehr** (31.10.2026, auf Ansage, Punkt 8 der Nutzer-Analyse:
    // „zu viel auf kleinem Raum"). Vorher stand davor ein Kästchen H/A bzw.
    // „Heim"/„Auswärts" — eine Auskunft, die beim Aufstellen kaum jemand
    // braucht und die Zeile um ein Element in 9 Punkt voller machte.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (team != null)
          TeamBadge(team: team, size: wappen)
        else
          Text(
            vereinsKuerzel(spiel.gegner),
            style: stil.copyWith(fontWeight: FontWeight.w700),
          ),
        if (mitZeit) ...[
          const SizedBox(width: 5),
          Text(anpfiffKurz(spiel.anpfiff), style: stil),
        ],
      ],
    );
  }
}
