import 'package:flutter/material.dart';

import '../farben.dart';
import '../typografie.dart';
import 'karte.dart';

// Aus `fantasy_league_screen.dart` hierher gezogen (09.11.2026), als die
// Tippspiel-Übersicht dieselben Zeilen bekam: zwei Übersichten, eine
// Zeilenform.

/// Eine Gruppe von [LigaZeile] auf **eigener Fläche**.
///
/// Vorher lagen die Zeilen nackt auf dem Grund des Schirms, nur durch
/// Haarlinien getrennt. Zwischen dem Duell-Kasten oben und dem Spieltag unten —
/// beides Bereiche mit Fläche und Inhalt — war die Mitte damit das Flachste,
/// was es gibt: fünf Wörter untereinander. „Trostlos" war die Rückmeldung, und
/// sie war berechtigt.
///
/// Dieselbe Sprache wie die Karten auf dem Startbildschirm: Kartengrund,
/// Haarlinie, runde Ecken. **Keine gefüllten Kacheln** — die gab es hier
/// schon einmal als „Schnellzugriff" und sie nahmen den halben Schirm ein.
class Zeilengruppe extends StatelessWidget {
  const Zeilengruppe(this.zeilen, {super.key});

  final List<Widget> zeilen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      // Dieselbe Hülle wie der Rückblick und der MatchUp-Kasten: eine Kante
      // für alle. Die Zeilen bringen ihren eigenen Innenabstand mit, deshalb
      // hat die Karte hier keinen.
      child: Karte(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < zeilen.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: 68,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.07),
                  ),
                zeilen[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LigaZeile extends StatelessWidget {
  const LigaZeile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.hinweis,
    this.zahl = 0,
  });

  final String label;
  final IconData icon;

  /// `null` = die Zeile ist da, aber (noch) nicht bedienbar. Sie bekommt dann
  /// **kein** `InkWell`: Eine Zeile, die auf Tippen reagiert und nichts tut,
  /// verspricht etwas, das es nicht gibt.
  final VoidCallback? onTap;

  /// Leiser Zusatz rechts („läuft", „3 dabei").
  final String? hinweis;

  /// Roter Zähler — etwas wartet auf dich.
  final int zahl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: [label, ?hinweis, if (zahl > 0) '$zahl offen'].join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  // **Grau, nicht bunt** (Design-Ideen Punkt 3, 15.10.2026).
                  // Fünf Kreise in fünf Farben sagten nur „hier ist eine
                  // Zeile"; Farbe trägt in dieser Zeile allein, was wartet —
                  // der rote Zähler und der goldene Auftrag.
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.onSurface.withValues(alpha: 0.07),
                  ),
                  child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  // **Der Hinweis steht jetzt unter dem Wort, nicht daneben.**
                  // Rechtsbündig war er ein Zusatz, den man übersah; als zweite
                  // Zeile gibt er der Zeile Inhalt. Fünf Zeilen, die alle nur
                  // ein Wort trugen, waren zwischen dem Duell-Kasten oben und
                  // dem Spieltag unten das Flachste auf dem Schirm.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      if (hinweis != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                hinweis!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: Schrift.label,
                                  fontWeight: FontWeight.w500,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (zahl > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.farben.rot,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$zahl',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Der Pfeil sitzt in einer kleinen Mulde: Er bleibt leise, liest
                // sich aber als Knopf statt als Satzzeichen.
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
