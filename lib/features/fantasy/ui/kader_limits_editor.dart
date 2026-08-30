import 'package:flutter/material.dart';

import '../models/fantasy_models.dart';
import 'wert_stepper.dart';

/// **Der Editor für die Kader-Limits — an zwei Stellen benutzt.**
///
/// Er saß in der Einstellungsseite und war damit an eine **bestehende** Liga
/// gebunden. Beim Erstellen gibt es die aber noch nicht: Dort wird eine
/// `RosterConfig` im Speicher zusammengebaut und erst am Ende abgeschickt.
/// Deshalb kennt der Editor keine Liga, nur die Kaderform und die aktuellen
/// Limits — und meldet Änderungen nach oben.
///
/// Die Alternative wäre gewesen, die vier Zeilen im Erstellen-Schirm ein
/// zweites Mal zu bauen. Sie tragen aber Regeln (Untergrenze je Position,
/// Vorschlag beim Einschalten, wann die Summe reichen muss), und zwei
/// Fassungen davon laufen beim nächsten Feinschliff auseinander.
class KaderLimitsEditor extends StatelessWidget {
  const KaderLimitsEditor({
    super.key,
    required this.roster,
    required this.limits,
    required this.onChanged,
  });

  /// Die Kaderform, aus der Unter- und Obergrenzen folgen.
  final RosterConfig roster;

  /// Limit je Position, `null` = keine Einschränkung.
  final Map<PlayerPosition, int?> limits;

  final ValueChanged<Map<PlayerPosition, int?>> onChanged;

  static const bezeichnung = {
    PlayerPosition.gk: 'Torhüter',
    PlayerPosition.def: 'Abwehr',
    PlayerPosition.mid: 'Mittelfeld',
    PlayerPosition.fwd: 'Sturm',
  };

  static const _symbol = {
    PlayerPosition.gk: Icons.sports_handball,
    PlayerPosition.def: Icons.shield_outlined,
    PlayerPosition.mid: Icons.hub_outlined,
    PlayerPosition.fwd: Icons.sports_soccer,
  };

  /// Untergrenze je Position: Unter der Startelf-Mindestzahl wäre keine
  /// gültige Aufstellung mehr möglich.
  static int minFuer(RosterConfig r, PlayerPosition pos) => switch (pos) {
        PlayerPosition.gk => r.gk,
        PlayerPosition.def => r.defMin,
        PlayerPosition.mid => r.midMin,
        PlayerPosition.fwd => r.fwdMin,
      };

  /// Vorschlag beim Einschalten: die Startelf-Obergrenze plus eine Reserve.
  /// Erlaubt jede gültige Formation und verhindert trotzdem das Horten.
  static int vorschlagFuer(RosterConfig r, PlayerPosition pos) =>
      switch (pos) {
        PlayerPosition.gk => r.gk + 1,
        PlayerPosition.def => r.defMax + 1,
        PlayerPosition.mid => r.midMax + 1,
        PlayerPosition.fwd => r.fwdMax + 1,
      };

  /// Trägt die Summe den Kader?
  ///
  /// **Die Rechnung gilt nur, wenn alle vier gedeckelt sind.** Bleibt eine
  /// Position offen, nimmt sie jede Restmenge auf; „zusammen 12 von 16" wäre
  /// dann eine Warnung vor einem Problem, das es nicht gibt.
  static bool reichtFuerKader(
      RosterConfig r, Map<PlayerPosition, int?> limits) {
    final alle = limits.length == PlayerPosition.values.length &&
        limits.values.every((v) => v != null);
    if (!alle) return true;
    return limits.values.fold(0, (int a, v) => a + (v ?? 0)) >= r.squadSize;
  }

  /// Was unter den Zeilen steht — drei Lagen, nicht eine.
  static String hinweisText(
      RosterConfig r, Map<PlayerPosition, int?> limits) {
    final gesetzt = limits.values.where((v) => v != null).length;
    if (gesetzt == 0) {
      return 'Keine Position ist begrenzt — es gilt keine Obergrenze.';
    }
    if (gesetzt < PlayerPosition.values.length) {
      final offen = [
        for (final pos in PlayerPosition.values)
          if (limits[pos] == null) bezeichnung[pos]!,
      ];
      return 'Ohne Limit: ${offen.join(', ')}. Dort passt beliebig viel in den '
          'Kader, die Rechnung geht also immer auf.';
    }
    final summe = limits.values.fold(0, (int a, v) => a + (v ?? 0));
    return reichtFuerKader(r, limits)
        ? 'Zusammen $summe Plätze bei ${r.squadSize} Kaderplätzen.'
        : 'Zusammen nur $summe Plätze, der Kader hat aber ${r.squadSize}. '
            'So findet der Draft irgendwann keinen erlaubten Spieler mehr und '
            'bricht ab.';
  }

  void _setze(PlayerPosition pos, int? wert) =>
      onChanged({...limits, pos: wert});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Jede Position steht für sich: Man kann die Torhüter deckeln und
        // Mittelfeld und Sturm offen lassen. Eine Position ohne Limit ist kein
        // halb eingeschalteter Zustand, sondern der Normalfall.
        for (final pos in PlayerPosition.values)
          _LimitZeile(
            icon: _symbol[pos]!,
            label: bezeichnung[pos]!,
            wert: limits[pos],
            min: minFuer(roster, pos),
            onEin: () => _setze(pos, vorschlagFuer(roster, pos)),
            onAus: () => _setze(pos, null),
            onWert: (v) => _setze(pos, v),
          ),
      ],
    );
  }
}

/// Eine Positionszeile der Kader-Limits.
///
/// Eigene Zeile statt einer `_SettingRow`: Dessen `ListTile` gibt dem `trailing` nur
/// begrenzt Platz, und hier stehen dort bis zu drei Bedienelemente. Die
/// Breiten kontrolliere ich lieber selbst, als sie zu schätzen.
///
/// Ohne Limit steht rechts ein Knopf statt einer Null — „0" hieße *keiner
/// erlaubt*, das Gegenteil von *unbegrenzt*.
class _LimitZeile extends StatelessWidget {
  const _LimitZeile({
    required this.icon,
    required this.label,
    required this.wert,
    required this.min,
    required this.onEin,
    required this.onAus,
    required this.onWert,
  });

  final IconData icon;
  final String label;

  /// `null` = diese Position ist nicht begrenzt.
  final int? wert;
  final int min;
  final VoidCallback onEin;
  final VoidCallback onAus;
  final ValueChanged<int> onWert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (wert == null)
            TextButton(
              onPressed: onEin,
              child: const Text('ohne Limit'),
            )
          else ...[
            WertStepper(
              label: label,
              value: wert!,
              min: min,
              max: 15,
              onChanged: onWert,
            ),
            IconButton(
              tooltip: 'Limit für $label aufheben',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onAus,
            ),
          ],
        ],
      ),
    );
  }
}

/// Kurzer Hinweis unter den Steppern; rot, wenn die Einstellung nicht aufgeht.
