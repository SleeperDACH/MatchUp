import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Eine auswählbare Option mit Symbol, Titel und einer Zeile Begründung.
///
/// Für Entscheidungen, bei denen die Wahl erklärt gehört — Liga-Modus,
/// Sichtbarkeit. Ein Segmented-Button oder Chip zeigt nur zwei Wörter; welche
/// Folgen die Wahl hat, stand dann bestenfalls in einem Hinweis darunter, der
/// sich beim Umschalten änderte.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.icon,
    required this.titel,
    required this.untertitel,
    required this.selected,
    required this.onTap,
    this.farbe,
  });

  final IconData icon;
  final String titel;
  final String untertitel;
  final bool selected;
  final VoidCallback onTap;

  /// Farbe des ausgewählten Zustands; ohne Angabe das Markengrün.
  final Color? farbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ton = farbe ?? MatchUpColors.green;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? ton.withValues(alpha: 0.14) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? ton.withValues(alpha: 0.75)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20, color: selected ? ton : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(untertitel,
                        style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? ton : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
