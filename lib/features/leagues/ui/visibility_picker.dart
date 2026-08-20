import 'package:flutter/material.dart';

import '../../../core/ui/option_tile.dart';

/// Auswahl der Sichtbarkeit (privat/öffentlich) und – bei öffentlich – des
/// Beitrittsmodus (freier Eintritt / auf Einladung). Wiederverwendet in der
/// Erstellung und den Einstellungen von Fantasy-Ligen und Tipprunden.
class VisibilityPicker extends StatelessWidget {
  const VisibilityPicker({
    super.key,
    required this.visibility,
    required this.joinPolicy,
    required this.onChanged,
  });

  /// `private` oder `public`.
  final String visibility;

  /// `open` oder `invite` (nur bei `public` relevant).
  final String joinPolicy;

  /// Liefert die neue Kombination (visibility, joinPolicy).
  final void Function(String visibility, String joinPolicy) onChanged;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == 'public';
    final isInvite = joinPolicy == 'invite';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Zwei Optionen mit Begründung statt eines Segmented-Buttons: was
        // „öffentlich" bedeutet, gehört an die Option — nicht in einen
        // Hinweis darunter, der sich beim Umschalten ändert.
        OptionTile(
          icon: Icons.lock_outline,
          titel: 'Privat',
          untertitel: 'Nur per Einladungscode oder Chat-Einladung.',
          selected: !isPublic,
          onTap: () => onChanged('private', joinPolicy),
        ),
        const SizedBox(height: 8),
        OptionTile(
          icon: Icons.public,
          titel: 'Öffentlich',
          untertitel: 'In der Suche findbar.',
          selected: isPublic,
          onTap: () => onChanged('public', joinPolicy),
        ),
        if (isPublic) ...[
          const SizedBox(height: 10),
          OptionTile(
            icon: Icons.door_front_door_outlined,
            titel: 'Freier Eintritt',
            untertitel: 'Jeder kann direkt beitreten.',
            selected: !isInvite,
            onTap: () => onChanged('public', 'open'),
          ),
          const SizedBox(height: 8),
          OptionTile(
            icon: Icons.how_to_reg_outlined,
            titel: 'Auf Einladung',
            untertitel: 'Beitritt erst nach deiner Bestätigung.',
            selected: isInvite,
            onTap: () => onChanged('public', 'invite'),
          ),
        ],
      ],
    );
  }
}
