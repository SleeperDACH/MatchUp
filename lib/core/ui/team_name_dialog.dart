import 'package:flutter/material.dart';

/// Dialog zum Setzen/Ändern des ligaspezifischen Teamnamens. Gibt den neuen
/// Namen zurück (leerer String = zurücksetzen auf den Nutzernamen) oder `null`,
/// wenn abgebrochen wurde.
Future<String?> showTeamNameDialog(BuildContext context,
    {String? current}) async {
  final controller = TextEditingController(text: current ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Teamname in dieser Liga'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Wird in dieser Liga überall statt deines Nutzernamens angezeigt. '
            'Leer = wieder dein Nutzername.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: const InputDecoration(
              labelText: 'Teamname',
              contentPadding: EdgeInsets.symmetric(horizontal: 12),
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
