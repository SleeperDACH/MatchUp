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
/// eine kleine Marke davor sagt Heim oder Auswärts (H/A, im Kader das Wort),
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
    this.buchstabe = false,
  });

  final NaechstesSpiel spiel;
  final double wappen;
  final Color? farbe;
  final double groesse;

  /// Tag und Anstoß dahinter (MatchUp). Ohne Zeit (Kader) steht „Heim"
  /// bzw. „Auswärts" ausgeschrieben statt der Kurzmarke.
  final bool mitZeit;

  /// H/A im Kästchen auch ohne Zeit — für die Zeile unter dem Namensschild
  /// auf dem Rasen, wo „Auswärts" die Schrift zu klein zwang (21.10.2026).
  final bool buchstabe;

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
    // **Heim/Auswärts als Marke, nicht als „@"** (19.10.2026, auf Ansage).
    // Mit Zeit ein Buchstabe im Kästchen (H/A), ohne Zeit das Wort.
    final marke = (mitZeit || buchstabe)
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: f.withValues(alpha: 0.5), width: 0.8),
            ),
            child: Text(
              spiel.heim ? 'H' : 'A',
              style: stil.copyWith(
                fontSize: Schrift.mikro,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : Text(spiel.heim ? 'Heim' : 'Auswärts', style: stil);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        marke,
        const SizedBox(width: 5),
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
