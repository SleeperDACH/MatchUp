import 'package:flutter/material.dart';

/// Dialog zum Umbenennen einer Liga/Tipprunde. Gibt den neuen (getrimmten)
/// Namen zurück oder `null` bei Abbruch / zu kurzem Namen (< 3 Zeichen).
Future<String?> showRenameLeagueDialog(BuildContext context,
    {required String current}) async {
  final controller = TextEditingController(text: current);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Liga-Name ändern'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name der Liga',
            helperText: '3–64 Zeichen',
          ),
          onSubmitted: (_) =>
              Navigator.of(ctx).pop(controller.text.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Speichern')),
        ],
      );
    },
  );
  controller.dispose();
  if (result == null || result.trim().length < 3) return null;
  return result.trim();
}
