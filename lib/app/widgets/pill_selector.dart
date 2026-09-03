import 'package:flutter/material.dart';

import '../theme.dart';

/// Auswahl-Pille in der Sprache der [SegmentedTabBar]: aktiv eine weich
/// gefüllte grüne Pille mit grüner Schrift, inaktiv nur gedämpfter Text.
///
/// Ersetzt `ChoiceChip` und `SegmentedButton`, die ihre Farben aus der
/// Material-Vorgabe ziehen (`secondaryContainer` — im dunklen Schema ein
/// stumpfes Oliv) und dazu einen Rahmen mitbringen, den der übrige Look
/// nirgends hat.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailing,
    this.centered = false,
    this.outlined = false,
    this.gedaempft = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// **Da, aber nicht wählbar.** Gedämpft statt weggelassen: „geht nicht" ist
  /// ein anderer Zustand als „gibt es nicht", und wer zählt, soll auf
  /// dieselbe Zahl kommen wie die Regel.
  final bool gedaempft;

  /// Optionales Symbol oder Wappen vor der Beschriftung.
  final Widget? leading;

  /// Optionales Zeichen dahinter (z. B. ein Haken bei Mehrfachauswahl).
  final Widget? trailing;

  /// Im [PillSelector] füllt die Pille ihr Segment und die Beschriftung gehört
  /// mittig; einzeln stehend schmiegt sie sich an den Text.
  final bool centered;

  /// Mit feiner Kante. Frei stehende Pillen (Mehrfachauswahl in einem `Wrap`)
  /// brauchen sie, damit man sieht, dass sie antippbar sind — in einer
  /// gemeinsamen Spur genügt die Füllung.
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (gedaempft) {
      // Halb durchsichtig, aber weiterhin antippbar — der Tipp erklärt dann,
      // warum es nicht geht.
      return Opacity(opacity: 0.38, child: _pille(context, scheme));
    }
    return _pille(context, scheme);
  }

  Widget _pille(BuildContext context, ColorScheme scheme) {
    // **Gewählt ist hell, nicht grün** (auf Ansage, 03.09.2026). Grün heißt in
    // dieser App „hier läuft etwas"; eine Pille, auf der man steht, läuft
    // nicht. Und drei grüne Signale übereinander — Fläche, Rahmen, Schrift —
    // waren für einen Filter zu viel. Der Kontrast kommt jetzt aus Helligkeit,
    // wie beim gefüllten Knopf und in der Navigationsleiste.
    return Material(
      color: selected
          ? MatchUpColors.snow.withValues(alpha: 0.14)
          : Colors.transparent,
      // Entweder `shape` **oder** `borderRadius` — `Material` verbietet
      // beides zusammen per Assertion.
      borderRadius: outlined ? null : BorderRadius.circular(11),
      shape: outlined
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
              side: BorderSide(
                color: selected
                    ? MatchUpColors.snow.withValues(alpha: 0.55)
                    : scheme.outlineVariant,
              ),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            leading == null ? 14 : 9,
            8,
            trailing == null ? 14 : 9,
            8,
          ),
          child: Row(
            mainAxisSize: centered ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 6)],
              // Flexibel: Bei langen Beschriftungen oder großer Systemschrift
              // soll die Pille kürzen statt überzulaufen.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected
                        ? MatchUpColors.snow
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Zwei oder mehr [PillChip] als Umschalter nebeneinander, gemeinsam in einer
/// dezent abgesetzten Spur — damit erkennbar bleibt, dass die Auswahl
/// zusammengehört.
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.options,
    required this.value,
    required this.onSelect,
  });

  /// Wert → Beschriftung, in Anzeigereihenfolge.
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final e in options.entries)
            Expanded(
              child: PillChip(
                label: e.value,
                selected: e.key == value,
                centered: true,
                onTap: () => onSelect(e.key),
              ),
            ),
        ],
      ),
    );
  }
}
