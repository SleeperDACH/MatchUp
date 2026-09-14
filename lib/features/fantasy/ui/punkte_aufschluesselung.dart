/// **Die Punkte-Aufschlüsselung, an einer Stelle.**
///
/// Sie lag privat im Spielerprofil und war damit für den MatchUp-Tab
/// unerreichbar — dort steht dieselbe Zahl in der Punktebox, und die Frage
/// „woher kommt die?" stellt sich beim Vergleich zweier Aufstellungen eher
/// als im Profil. Eine zweite Fassung daneben wäre die nächste Stelle, an der
/// zwei Darstellungen derselben Rechnung auseinanderlaufen.
library;

import 'package:flutter/material.dart';

import '../logic/fantasy_scoring_engine.dart';

/// Öffnet die Aufschlüsselung als Blatt von unten.
void zeigePunkteAufschluesselung(
  BuildContext context, {
  required String titel,
  required PlayerScore score,
  required bool gespielt,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => PunkteAufschluesselung(
      titel: titel,
      score: score,
      gespielt: gespielt,
    ),
  );
}

/// Die Punkte eines Spieltags im Einzelnen: jede Zeile der Wertung mit Anzahl,
/// Einzelwert und Summe.
///
/// Eine Punktzahl allein sagt nicht, woher sie kommt — 6 Punkte können ein
/// halbes Spiel sein oder ein Tor minus zwei Gegentore. Die Aufschlüsselung
/// kommt aus derselben Funktion, die auch wertet (`scorePlayerDetailed`); eine
/// zweite Rechnung fürs Anzeigen wäre eine zweite Wahrheit.
class PunkteAufschluesselung extends StatelessWidget {
  const PunkteAufschluesselung({
    super.key,
    required this.titel,
    required this.score,
    required this.gespielt,
  });

  final String titel;
  final PlayerScore score;
  final bool gespielt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titel,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (!gespielt)
              const _Leer('An diesem Spieltag nicht eingesetzt.')
            else if (score.breakdown.isEmpty)
              const _Leer('Keine wertbaren Aktionen.')
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in score.breakdown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(l.label)),
                            if (l.count != 1) ...[
                              Text(
                                '${l.count} ×',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: 56,
                              child: Text(
                                formatPoints(l.subtotal),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                  // Rot markiert den Abzug — die Ausnahme.
                                  // Der Normalfall braucht keine Farbe.
                                  color: l.subtotal < 0
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Gesamt',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          formatPoints(score.total),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: score.total < 0
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ein leerer Zustand mit Begründung — nie eine leere Fläche.
class _Leer extends StatelessWidget {
  const _Leer(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
