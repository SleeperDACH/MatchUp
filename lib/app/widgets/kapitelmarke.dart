import 'package:flutter/material.dart';

import '../typografie.dart';

/// **Die Kapitelmarke der App.**
///
/// Ein farbiger Strich, ein Wort in Versalien, eine Haarlinie bis zum Rand.
/// Sie gliedert einen Schirm, ohne eine Karte um die Gruppe zu ziehen — das
/// ist der Unterschied zur früheren Bauweise, in der jede Rubrik einen eigenen
/// Kasten bekam und der Schirm aus lauter Kästen bestand.
///
/// Sie stand bisher **viermal** im Code (Fantasy-Einstellungen, Waiver-Anträge,
/// Freunde, Profil), jedes Mal leicht anders: mal mit Strich, mal ohne, mal
/// 26 Punkt Luft darüber, mal 20. Wer eine Rubrik anlegte, kopierte die
/// nächstbeste. Hier steht sie einmal.
///
/// [farbe] ist der Strich links. Sie ordnet zu („das gehört zum Tippspiel"),
/// sie ruft nicht — deshalb ist sie 3 Punkt breit und nicht die Schriftfarbe.
class Kapitelmarke extends StatelessWidget {
  const Kapitelmarke(
    this.text, {
    super.key,
    this.farbe,
    this.obenLuft = Abstand.l,
  });

  final String text;
  final Color? farbe;

  /// Luft über der Marke. Der Regelfall trennt zwei Rubriken; wer sie als
  /// erste Zeile eines Schirms setzt, nimmt weniger.
  final double obenLuft;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, obenLuft, 0, Abstand.s),
      child: Row(
        children: [
          if (farbe != null) ...[
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: farbe,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: Schrift.marke,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 0.8,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
