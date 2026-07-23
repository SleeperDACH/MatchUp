import 'package:flutter/material.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final isPublic = visibility == 'public';
    final isInvite = joinPolicy == 'invite';

    String hint;
    if (!isPublic) {
      hint = 'Nur per Einladungscode oder Chat-Einladung beitretbar.';
    } else if (isInvite) {
      hint = 'In der Suche findbar; Beitritt nur nach deiner Bestätigung '
          'einer Anfrage.';
    } else {
      hint = 'In der Suche findbar; jeder kann direkt beitreten.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'private',
                label: Text('Privat'),
                icon: Icon(Icons.lock_outline)),
            ButtonSegment(
                value: 'public',
                label: Text('Öffentlich'),
                icon: Icon(Icons.public)),
          ],
          selected: {isPublic ? 'public' : 'private'},
          onSelectionChanged: (s) => onChanged(s.first, joinPolicy),
        ),
        if (isPublic) ...[
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'open', label: Text('Freier Eintritt')),
              ButtonSegment(value: 'invite', label: Text('Auf Einladung')),
            ],
            selected: {isInvite ? 'invite' : 'open'},
            onSelectionChanged: (s) => onChanged('public', s.first),
          ),
        ],
        const SizedBox(height: 8),
        Text(hint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}
